// Fuente unica de verdad del seed y de la matriz RLS.
// Todos los datos son ficticios y solo pueden existir en branch/staging.

export const PRODUCTION_PROJECT_REF = 'dctqcbznekcyxhjujuci';

export const USERS = Object.freeze([
  {
    key: 'gerencia',
    email: 'gerencia.crm@demo.avancecorp.pe',
    name: 'GERENCIA DEMO',
    portalRole: 'comercial',
    crmRole: 'gerencia',
    supervisorKey: null,
    portalActive: true,
    crmActive: true,
  },
  {
    key: 'sup1',
    email: 'sup1.crm@demo.avancecorp.pe',
    name: 'SUPERVISOR UNO',
    portalRole: 'comercial',
    crmRole: 'supervisor',
    supervisorKey: null,
    portalActive: true,
    crmActive: true,
  },
  {
    key: 'sup2',
    email: 'sup2.crm@demo.avancecorp.pe',
    name: 'SUPERVISOR DOS',
    portalRole: 'comercial',
    crmRole: 'supervisor',
    supervisorKey: null,
    portalActive: true,
    crmActive: true,
  },
  {
    key: 'sup1Nested',
    email: 'sup-anidado.crm@demo.avancecorp.pe',
    name: 'SUPERVISOR ANIDADO',
    portalRole: 'comercial',
    crmRole: 'supervisor',
    supervisorKey: 'sup1',
    portalActive: true,
    crmActive: true,
  },
  {
    key: 'vend1',
    email: 'vend1.crm@demo.avancecorp.pe',
    name: 'VENDEDOR UNO',
    portalRole: 'comercial',
    crmRole: 'vendedor',
    supervisorKey: 'sup1',
    portalActive: true,
    crmActive: true,
  },
  {
    key: 'vend2',
    email: 'vend2.crm@demo.avancecorp.pe',
    name: 'VENDEDOR DOS',
    portalRole: 'comercial',
    crmRole: 'vendedor',
    supervisorKey: 'sup1',
    portalActive: true,
    crmActive: true,
  },
  {
    key: 'vend3',
    email: 'vend3.crm@demo.avancecorp.pe',
    name: 'VENDEDOR TRES',
    portalRole: 'comercial',
    crmRole: 'vendedor',
    supervisorKey: 'sup2',
    portalActive: true,
    crmActive: true,
  },
  {
    key: 'vend4',
    email: 'vend4.crm@demo.avancecorp.pe',
    name: 'VENDEDOR CUATRO',
    portalRole: 'comercial',
    crmRole: 'vendedor',
    supervisorKey: 'sup2',
    portalActive: true,
    crmActive: true,
  },
  {
    key: 'vendNested',
    email: 'vend-anidado.crm@demo.avancecorp.pe',
    name: 'VENDEDOR ANIDADO',
    portalRole: 'comercial',
    crmRole: 'vendedor',
    supervisorKey: 'sup1Nested',
    portalActive: true,
    crmActive: true,
  },
  {
    key: 'vendInactive',
    email: 'vend-inactivo.crm@demo.avancecorp.pe',
    name: 'VENDEDOR INACTIVO',
    portalRole: 'comercial',
    crmRole: 'vendedor',
    supervisorKey: 'sup2',
    portalActive: false,
    crmActive: false,
  },
  {
    key: 'directorio',
    email: 'directorio.crm@demo.avancecorp.pe',
    name: 'DIRECTORIO DEMO',
    portalRole: 'directorio',
    crmRole: null,
    supervisorKey: null,
    portalActive: true,
    crmActive: null,
  },
  {
    key: 'clientBank',
    email: 'cliente-bancario.crm@demo.avancecorp.pe',
    name: 'CLIENTE BANCARIO DEMO',
    portalRole: 'cliente',
    crmRole: null,
    supervisorKey: null,
    portalActive: true,
    crmActive: null,
  },
]);

export const USER_BY_KEY = Object.freeze(
  Object.fromEntries(USERS.map((user) => [user.key, user])),
);

export const LEADS = Object.freeze([
  {
    key: 'juan',
    id: '11000000-0000-4000-8000-000000000001',
    activityId: '22000000-0000-4000-8000-000000000001',
    name: 'JUAN PEREZ DEMO',
    phone: '987654321',
    sellerKey: 'vend1',
    supervisorKey: null,
    stage: 'nuevo',
    estimatedAmount: 15000,
    currency: 'PEN',
  },
  {
    key: 'maria',
    id: '11000000-0000-4000-8000-000000000002',
    activityId: '22000000-0000-4000-8000-000000000002',
    name: 'MARIA LOPEZ DEMO',
    phone: '987654322',
    sellerKey: 'vend1',
    supervisorKey: null,
    stage: 'contactado',
    estimatedAmount: 30000,
    currency: 'PEN',
  },
  {
    key: 'carlos',
    id: '11000000-0000-4000-8000-000000000003',
    activityId: '22000000-0000-4000-8000-000000000003',
    name: 'CARLOS RUIZ DEMO',
    phone: '987654323',
    sellerKey: 'vendNested',
    supervisorKey: null,
    stage: 'reunion_agendada',
    estimatedAmount: 10000,
    currency: 'USD',
  },
  {
    key: 'ana',
    id: '11000000-0000-4000-8000-000000000004',
    activityId: '22000000-0000-4000-8000-000000000004',
    name: 'ANA TORRES DEMO',
    phone: '987654324',
    sellerKey: 'vend3',
    supervisorKey: null,
    stage: 'propuesta_enviada',
    estimatedAmount: 50000,
    currency: 'PEN',
  },
  {
    key: 'luis',
    id: '11000000-0000-4000-8000-000000000005',
    activityId: '22000000-0000-4000-8000-000000000005',
    name: 'LUIS GARCIA DEMO',
    phone: '987654325',
    sellerKey: null,
    supervisorKey: 'sup1',
    stage: 'nuevo',
    estimatedAmount: null,
    currency: 'PEN',
  },
  {
    key: 'rosa',
    id: '11000000-0000-4000-8000-000000000006',
    activityId: '22000000-0000-4000-8000-000000000006',
    name: 'ROSA DIAZ DEMO',
    phone: '987654326',
    sellerKey: null,
    supervisorKey: 'sup2',
    stage: 'nuevo',
    estimatedAmount: null,
    currency: 'PEN',
  },
  {
    key: 'inactiveOwned',
    id: '11000000-0000-4000-8000-000000000007',
    activityId: '22000000-0000-4000-8000-000000000007',
    name: 'LEAD DE VENDEDOR INACTIVO DEMO',
    phone: '987654327',
    sellerKey: 'vendInactive',
    supervisorKey: null,
    stage: 'nuevo',
    estimatedAmount: 7000,
    currency: 'PEN',
  },
]);

export const LEAD_BY_KEY = Object.freeze(
  Object.fromEntries(LEADS.map((lead) => [lead.key, lead])),
);

const leadNames = (...keys) => keys.map((key) => LEAD_BY_KEY[key].name).sort();

// Esta matriz es consumida directamente por test-rls.mjs. Supervisor 1 ve 4:
// dos de vend1, uno del vendedor nieto (vendNested) y su lead parkeado.
export const EXPECTED_LEAD_NAMES = Object.freeze({
  gerencia: leadNames('juan', 'maria', 'carlos', 'ana', 'luis', 'rosa', 'inactiveOwned'),
  sup1: leadNames('juan', 'maria', 'carlos', 'luis'),
  sup2: leadNames('ana', 'rosa', 'inactiveOwned'),
  sup1Nested: leadNames('carlos'),
  vend1: leadNames('juan', 'maria'),
  vend2: [],
  vend3: leadNames('ana'),
  vend4: [],
  vendNested: leadNames('carlos'),
  vendInactive: [],
  directorio: leadNames('juan', 'maria', 'carlos', 'ana', 'luis', 'rosa', 'inactiveOwned'),
  clientBank: [],
});

export const BANK_CLIENT = Object.freeze({
  key: 'clientBank',
  dni: '90000001',
  phone: '900000001',
  adviserKey: 'vend1',
  bank: 'BANCO DEMO',
  accountNumber: '19100000000001',
  accountType: 'ahorros',
  cci: '00219100000000000001',
  bankUsd: 'BANCO DEMO USD',
  accountNumberUsd: '19100000000002',
  accountTypeUsd: 'ahorros',
  cciUsd: '00219100000000000002',
});

export const BANK_CONTRACT = Object.freeze({
  id: '33000000-0000-4000-8000-000000000001',
  number: '2026-01-990001',
  capital: 1000,
  currency: 'PEN',
  annualRate: 10,
  paymentMode: 'mensual',
  interestType: 'simple',
  startDate: '2026-01-01',
  endDate: '2027-01-01',
  category: 'nuevo',
  internalNotes: 'FIXTURE RLS: NO EXPONER AL CRM',
});

export const TRANSIENT_IDS = Object.freeze({
  directoryLead: '99000000-0000-4000-8000-000000000001',
  crossTeamLead: '99000000-0000-4000-8000-000000000002',
  directoryActivity: '99000000-0000-4000-8000-000000000003',
  crossTeamActivity: '99000000-0000-4000-8000-000000000004',
  portalClientLead: '99000000-0000-4000-8000-000000000005',
});

export function normalizePeruPhone(phone) {
  const digits = String(phone).replace(/[^0-9]/g, '');
  if (digits.length === 9) return `+51${digits}`;
  if (/^51[0-9]{9}$/.test(digits)) return `+${digits}`;
  return `+${digits}`;
}

export function validateFixtureModel() {
  const unique = (values, label) => {
    if (new Set(values).size !== values.length) {
      throw new Error(`Fixtures invalidos: ${label} contiene duplicados.`);
    }
  };

  unique(USERS.map((user) => user.key), 'user.key');
  unique(USERS.map((user) => user.email.toLowerCase()), 'user.email');
  unique(LEADS.map((lead) => lead.id), 'lead.id');
  unique(LEADS.map((lead) => lead.activityId), 'lead.activityId');
  unique(LEADS.map((lead) => lead.name), 'lead.name');
  unique(LEADS.map((lead) => normalizePeruPhone(lead.phone)), 'lead.phone');

  for (const user of USERS) {
    if (user.supervisorKey && !USER_BY_KEY[user.supervisorKey]?.crmRole) {
      throw new Error(`Fixtures invalidos: supervisor inexistente para ${user.key}.`);
    }
    const visited = new Set([user.key]);
    let cursor = user.supervisorKey;
    while (cursor) {
      if (visited.has(cursor)) {
        throw new Error(`Fixtures invalidos: ciclo jerarquico desde ${user.key}.`);
      }
      visited.add(cursor);
      cursor = USER_BY_KEY[cursor]?.supervisorKey ?? null;
    }
  }

  for (const lead of LEADS) {
    if (lead.sellerKey && USER_BY_KEY[lead.sellerKey]?.crmRole !== 'vendedor') {
      throw new Error(`Fixtures invalidos: vendedor inexistente para ${lead.key}.`);
    }
    if (lead.supervisorKey && USER_BY_KEY[lead.supervisorKey]?.crmRole !== 'supervisor') {
      throw new Error(`Fixtures invalidos: supervisor de parkeo invalido para ${lead.key}.`);
    }
    if (lead.sellerKey && lead.supervisorKey) {
      throw new Error(`Fixtures invalidos: ${lead.key} esta asignado y parkeado a la vez.`);
    }
  }

  const matrixKeys = Object.keys(EXPECTED_LEAD_NAMES).sort();
  const sessionKeys = USERS.map((user) => user.key).sort();
  if (JSON.stringify(matrixKeys) !== JSON.stringify(sessionKeys)) {
    throw new Error('Fixtures invalidos: la matriz no cubre exactamente todos los usuarios demo.');
  }

  const descendantsOf = (rootKey) => {
    const visible = new Set([rootKey]);
    let changed = true;
    while (changed) {
      changed = false;
      for (const user of USERS.filter((candidate) => candidate.crmRole)) {
        if (user.supervisorKey && visible.has(user.supervisorKey) && !visible.has(user.key)) {
          visible.add(user.key);
          changed = true;
        }
      }
    }
    return visible;
  };

  for (const user of USERS) {
    let expected = [];
    if (user.portalRole === 'directorio') {
      expected = LEADS.map((lead) => lead.name);
    } else if (user.crmRole && user.crmActive) {
      const visibleOwners = user.crmRole === 'gerencia'
        ? new Set(USERS.filter((candidate) => candidate.crmRole).map((candidate) => candidate.key))
        : descendantsOf(user.key);
      expected = LEADS.filter((lead) => {
        if (user.crmRole === 'gerencia') return true;
        if (lead.sellerKey) return visibleOwners.has(lead.sellerKey);
        return lead.supervisorKey ? visibleOwners.has(lead.supervisorKey) : false;
      }).map((lead) => lead.name);
    }
    const declared = [...EXPECTED_LEAD_NAMES[user.key]].sort();
    if (JSON.stringify(expected.sort()) !== JSON.stringify(declared)) {
      throw new Error(`Fixtures invalidos: matriz incoherente para ${user.key}.`);
    }
  }
}
