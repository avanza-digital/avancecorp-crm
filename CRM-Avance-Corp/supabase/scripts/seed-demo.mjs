// Seed determinista del CRM para un BRANCH de Supabase.
// Nunca se debe ejecutar contra produccion.
//
// Uso:
//   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... npm run seed:demo
//   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... npm run seed:preflight

import { createClient } from '@supabase/supabase-js';
import {
  BANK_CLIENT,
  BANK_CONTRACT,
  LEADS,
  PRODUCTION_PROJECT_REF,
  TAREAS,
  USERS,
  normalizePeruPhone,
  validateFixtureModel,
} from './fixtures.mjs';

const HELP = `
Seed demo del CRM (solo branch/staging)

Uso:
  node supabase/scripts/seed-demo.mjs [--preflight]

Opciones:
  --preflight  Valida runtime, variables y destino sin conectarse a Supabase.
  --help       Muestra esta ayuda sin exigir variables de entorno.

Variables requeridas:
  SUPABASE_URL
  SUPABASE_SERVICE_ROLE_KEY
  CRM_DEMO_PASSWORD       Password temporal de los usuarios demo (minimo 12).
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
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY?.trim();
const PASSWORD = process.env.CRM_DEMO_PASSWORD;

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
  if (!PASSWORD) fail('Falta CRM_DEMO_PASSWORD.');
  if (PASSWORD.length < 12) fail('CRM_DEMO_PASSWORD debe tener al menos 12 caracteres.');

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
    fail('Destino de PRODUCCION detectado. El seed solo corre en branch/staging.');
  }
}

function printPlan() {
  const crmUsers = USERS.filter((user) => user.crmRole);
  const activeCrmUsers = crmUsers.filter((user) => user.crmActive);
  console.log('✓ runtime y variables validos');
  console.log(`✓ destino permitido: ${new URL(SUPABASE_URL).host}`);
  console.log(`✓ plan: ${USERS.length} usuarios Auth/perfil`);
  console.log(`✓ plan: ${crmUsers.length} miembros CRM (${activeCrmUsers.length} activos, ${crmUsers.length - activeCrmUsers.length} inactivo)`);
  console.log(`✓ plan: ${LEADS.length} leads y ${LEADS.length} actividades deterministas`);
  console.log(`✓ plan: ${TAREAS.length} tareas de agenda deterministas (tenencia derivada del lead)`);
  console.log('✓ plan: 1 cliente bancario y 1 contrato sensible de prueba');
  console.log('Preflight terminado; no se abrio ninguna conexion.');
}

validateNode();
validateEnvironment();
validateFixtureModel();

if (args.has('--preflight')) {
  printPlan();
  process.exit(0);
}

const admin = createClient(SUPABASE_URL, SERVICE_KEY, {
  auth: {
    autoRefreshToken: false,
    detectSessionInUrl: false,
    persistSession: false,
  },
});

const ids = Object.create(null);

async function requireResponse(label, promise) {
  let response;
  try {
    response = await promise;
  } catch (error) {
    throw new Error(`${label}: ${error?.message ?? String(error)}`, { cause: error });
  }
  if (response.error) {
    throw new Error(`${label}: ${response.error.message}`, { cause: response.error });
  }
  return response;
}

async function findAuthUser(email) {
  const { data } = await requireResponse(
    `listar usuarios Auth para ${email}`,
    admin.auth.admin.listUsers({ page: 1, perPage: 1000 }),
  );
  return data.users.find((user) => user.email?.toLowerCase() === email.toLowerCase()) ?? null;
}

async function ensureAuthUser(user) {
  const created = await admin.auth.admin.createUser({
    email: user.email,
    email_confirm: true,
    password: PASSWORD,
  });

  let authUser = created.data?.user ?? null;
  if (created.error) {
    if (!/already|exists|registered/i.test(created.error.message)) {
      throw new Error(`crear usuario Auth ${user.email}: ${created.error.message}`, {
        cause: created.error,
      });
    }
    authUser = await findAuthUser(user.email);
  }

  if (!authUser?.id) {
    throw new Error(`No se pudo resolver el UUID Auth de ${user.email}.`);
  }

  await requireResponse(
    `restablecer credenciales demo de ${user.email}`,
    admin.auth.admin.updateUserById(authUser.id, {
      email_confirm: true,
      password: PASSWORD,
    }),
  );
  ids[user.key] = authUser.id;
}

async function ensureProfile(user) {
  const profile = {
    id: ids[user.key],
    activo: user.portalActive,
    correo: user.email,
    nombre_completo: user.name,
    rol: user.portalRole,
  };

  if (user.key === BANK_CLIENT.key) {
    Object.assign(profile, {
      asesor_perfil_id: ids[BANK_CLIENT.adviserKey],
      banco: BANK_CLIENT.bank,
      banco_usd: BANK_CLIENT.bankUsd,
      beneficiario_dni: null,
      beneficiario_dni_usd: null,
      beneficiario_nombre: null,
      beneficiario_nombre_usd: null,
      cci: BANK_CLIENT.cci,
      cci_usd: BANK_CLIENT.cciUsd,
      creado_por: ids[BANK_CLIENT.adviserKey],
      dni: BANK_CLIENT.dni,
      numero_cuenta: BANK_CLIENT.accountNumber,
      numero_cuenta_usd: BANK_CLIENT.accountNumberUsd,
      telefono: BANK_CLIENT.phone,
      tipo_cuenta: BANK_CLIENT.accountType,
      tipo_cuenta_usd: BANK_CLIENT.accountTypeUsd,
      titular_distinto: false,
      titular_distinto_usd: false,
    });
  }

  await requireResponse(
    `upsert public.perfiles (${user.key})`,
    admin.from('perfiles').upsert(profile, { onConflict: 'id' }),
  );
}

async function ensureTeam({ activateForSeed = false } = {}) {
  for (const user of USERS.filter((candidate) => candidate.crmRole)) {
    await requireResponse(
      `upsert crm.equipo (${user.key})`,
      admin.schema('crm').from('equipo').upsert({
        // 0C impide asignar responsabilidad NUEVA a un miembro inactivo. Para
        // construir el fixture historico "inactiveOwned" en un branch limpio,
        // se provisiona activo y se desactiva inmediatamente al terminar.
        activo: activateForSeed ? true : user.crmActive,
        perfil_id: ids[user.key],
        rol_crm: user.crmRole,
        supervisor_id: user.supervisorKey ? ids[user.supervisorKey] : null,
      }, { onConflict: 'perfil_id' }),
    );
  }
}

async function findExistingLead(fixture) {
  const byId = await requireResponse(
    `buscar lead ${fixture.key} por UUID`,
    admin.schema('crm').from('leads').select('id').eq('id', fixture.id).maybeSingle(),
  );
  if (byId.data) return byId.data;

  const byPhone = await requireResponse(
    `buscar lead ${fixture.key} por telefono`,
    admin.schema('crm').from('leads')
      .select('id')
      .eq('telefono', normalizePeruPhone(fixture.phone))
      .maybeSingle(),
  );
  return byPhone.data;
}

async function ensureLead(fixture) {
  const existing = await findExistingLead(fixture);
  const id = existing?.id ?? fixture.id;
  const payload = {
    activo: true,
    asignado_supervisor_id: fixture.supervisorKey ? ids[fixture.supervisorKey] : null,
    creado_por: ids.gerencia,
    etapa: fixture.stage,
    id,
    moneda: fixture.currency,
    monto_estimado: fixture.estimatedAmount,
    nombre_completo: fixture.name,
    nota: `FIXTURE RLS ${fixture.key}`,
    origen: 'oficina',
    telefono: fixture.phone,
    vendedor_id: fixture.sellerKey ? ids[fixture.sellerKey] : null,
  };

  const query = existing
    ? admin.schema('crm').from('leads').update(payload).eq('id', id).select('id').single()
    : admin.schema('crm').from('leads').insert(payload).select('id').single();
  const { data } = await requireResponse(`guardar lead ${fixture.key}`, query);
  return data.id;
}

async function ensureActivity(fixture, leadId) {
  await requireResponse(
    `upsert actividad ${fixture.key}`,
    admin.schema('crm').from('actividades').upsert({
      creado_por: ids.gerencia,
      detalle: `FIXTURE RLS ${fixture.key}`,
      id: fixture.activityId,
      lead_id: leadId,
      metadata: { fixture: 'crm-rls', key: fixture.key },
      tipo: 'nota',
    }, { onConflict: 'id' }),
  );
}

async function ensureTarea(fixture, leadId) {
  // Idempotente: se busca por id antes de insertar. Si ya existe NO se
  // reescribe: una tarea cerrada es inmutable por trigger y una pendiente no
  // debe acumular reprogramaciones por re-sembrar.
  const existing = await requireResponse(
    `buscar tarea ${fixture.key} por UUID`,
    admin.schema('crm').from('tareas').select('id').eq('id', fixture.id).maybeSingle(),
  );
  if (existing.data) return;

  // La tenencia NO se envia: la deriva el before-insert trigger del lead (los
  // leads fixture estan abiertos, asi que el insert pasa el gate del trigger).
  await requireResponse(
    `crear tarea ${fixture.key}`,
    admin.schema('crm').from('tareas').insert({
      creado_por: ids.gerencia,
      estado: fixture.estado,
      id: fixture.id,
      lead_id: leadId,
      tipo: fixture.tipo,
      titulo: fixture.titulo,
      vence_en: fixture.venceEn,
    }),
  );
}

async function ensureBankContract() {
  const existing = await requireResponse(
    'buscar contrato bancario fixture',
    admin.from('contratos')
      .select('id')
      .eq('numero_contrato', BANK_CONTRACT.number)
      .maybeSingle(),
  );
  const id = existing.data?.id ?? BANK_CONTRACT.id;
  const payload = {
    capital: BANK_CONTRACT.capital,
    categoria: BANK_CONTRACT.category,
    cliente_id: ids[BANK_CLIENT.key],
    creado_por: ids[BANK_CLIENT.adviserKey],
    estado: 'activo',
    fecha_inicio: BANK_CONTRACT.startDate,
    fecha_vencimiento: BANK_CONTRACT.endDate,
    id,
    modalidad: BANK_CONTRACT.paymentMode,
    moneda: BANK_CONTRACT.currency,
    notas_internas: BANK_CONTRACT.internalNotes,
    numero_contrato: BANK_CONTRACT.number,
    tasa_anual: BANK_CONTRACT.annualRate,
    tipo_interes: BANK_CONTRACT.interestType,
  };

  const query = existing.data
    ? admin.from('contratos').update(payload).eq('id', id).select('id').single()
    : admin.from('contratos').insert(payload).select('id').single();
  await requireResponse('guardar contrato bancario fixture', query);
}

async function main() {
  for (const user of USERS) await ensureAuthUser(user);
  console.log(`✓ ${USERS.length} usuarios Auth listos`);

  for (const user of USERS) await ensureProfile(user);
  console.log(`✓ ${USERS.length} perfiles del portal sincronizados`);

  await ensureTeam({ activateForSeed: true });
  try {
    const leadIdByKey = Object.create(null);
    for (const fixture of LEADS) {
      const leadId = await ensureLead(fixture);
      await ensureActivity(fixture, leadId);
      leadIdByKey[fixture.key] = leadId;
    }
    for (const fixture of TAREAS) {
      await ensureTarea(fixture, leadIdByKey[fixture.leadKey]);
    }
  } finally {
    // Tambien corre si falla un fixture: nunca deja habilitado por accidente al
    // usuario que el gate necesita comprobar como inactivo.
    await ensureTeam();
  }
  console.log(`✓ ${LEADS.length} leads y ${LEADS.length} actividades deterministas`);
  console.log(`✓ ${TAREAS.length} tareas de agenda deterministas`);

  const teamCount = USERS.filter((user) => user.crmRole).length;
  const inactiveCount = USERS.filter((user) => user.crmRole && !user.crmActive).length;
  console.log(`✓ crm.equipo: ${teamCount} miembros (${inactiveCount} inactivo)`);

  await ensureBankContract();
  console.log('✓ cliente bancario + contrato sensible de prueba');

  console.log('\nSeed listo. La password se tomo de CRM_DEMO_PASSWORD.');
  console.log(`Supervisor 1 debe ver 4 leads; total global: ${LEADS.length}.`);
}

main().catch((error) => {
  console.error(`✗ seed fatal: ${error?.message ?? String(error)}`);
  process.exit(1);
});
