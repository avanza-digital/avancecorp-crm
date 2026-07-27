// Fuente unica de verdad del seed y de la matriz RLS.
// Todos los datos son ficticios y solo pueden existir en branch/staging.

import { randomUUID } from 'node:crypto';

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
    // C1 — reparto de la cola. PRECONDICION DURA: portalRole debe ser
    // 'comercial' o 'analista', NUNCA 'directorio'/'admin'/'superadmin': un rol
    // de portal lector-global colapsaria el modelo de ambito vacio (veria leads
    // y PII de clientes por es_lector_global, saltandose las RPC).
    key: 'coordinador',
    email: 'coordinador.crm@demo.avancecorp.pe',
    name: 'COORDINADOR DEMO',
    portalRole: 'comercial',
    crmRole: 'coordinador',
    supervisorKey: null,
    portalActive: true,
    crmActive: true,
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
    estimatedAmount: 1000,
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
    estimatedAmount: 5000,
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
  // Coordinador (C1): ambito VACIO por diseno — no ve leads por RLS, solo por
  // las RPC SECURITY DEFINER de reparto (que proyectan sin PII de contacto).
  coordinador: [],
  directorio: leadNames('juan', 'maria', 'carlos', 'ana', 'luis', 'rosa', 'inactiveOwned'),
  clientBank: [],
});

// Agenda comercial: los fixtures NO declaran tenencia (vendedor_id /
// asignado_supervisor_id): la DERIVA el before-insert trigger del lead
// referenciado y los triggers de coherencia la mantienen. Por eso cada tarea
// solo apunta a un leadKey; la matriz esperada se computa desde ese lead.
export const TAREAS = Object.freeze([
  {
    key: 'llamadaJuan',
    id: '44000000-0000-4000-8000-000000000001',
    leadKey: 'juan',
    tipo: 'llamada',
    titulo: 'LLAMAR A JUAN PEREZ DEMO',
    venceEn: '2026-07-20T15:00:00Z',
    estado: 'pendiente',
  },
  {
    key: 'reunionCarlos',
    id: '44000000-0000-4000-8000-000000000002',
    leadKey: 'carlos',
    tipo: 'reunion',
    titulo: 'REUNION CON CARLOS RUIZ DEMO',
    venceEn: '2026-07-21T16:30:00Z',
    estado: 'pendiente',
  },
  {
    key: 'whatsappAna',
    id: '44000000-0000-4000-8000-000000000003',
    leadKey: 'ana',
    tipo: 'whatsapp',
    titulo: 'WHATSAPP A ANA TORRES DEMO',
    venceEn: '2026-07-22T14:00:00Z',
    estado: 'pendiente',
  },
  {
    key: 'bandejaLuis',
    id: '44000000-0000-4000-8000-000000000004',
    leadKey: 'luis',
    tipo: 'tarea',
    titulo: 'REVISAR LEAD PARKEADO LUIS DEMO',
    venceEn: '2026-07-23T13:00:00Z',
    estado: 'pendiente',
  },
  {
    key: 'bandejaRosa',
    id: '44000000-0000-4000-8000-000000000005',
    leadKey: 'rosa',
    tipo: 'tarea',
    titulo: 'REVISAR LEAD PARKEADO ROSA DEMO',
    venceEn: '2026-07-24T13:00:00Z',
    estado: 'pendiente',
  },
]);

export const TAREA_BY_KEY = Object.freeze(
  Object.fromEntries(TAREAS.map((tarea) => [tarea.key, tarea])),
);

const tareaTitulos = (...keys) => keys.map((key) => TAREA_BY_KEY[key].titulo).sort();

// Consumida por test-rls.mjs igual que EXPECTED_LEAD_NAMES: la visibilidad de
// una tarea es EXACTAMENTE la del lead del que cuelga (RLS calcada de leads_*).
export const EXPECTED_TAREA_TITULOS = Object.freeze({
  gerencia: tareaTitulos('llamadaJuan', 'reunionCarlos', 'whatsappAna', 'bandejaLuis', 'bandejaRosa'),
  sup1: tareaTitulos('llamadaJuan', 'reunionCarlos', 'bandejaLuis'),
  sup2: tareaTitulos('whatsappAna', 'bandejaRosa'),
  sup1Nested: tareaTitulos('reunionCarlos'),
  vend1: tareaTitulos('llamadaJuan'),
  vend2: [],
  vend3: tareaTitulos('whatsappAna'),
  vend4: [],
  vendNested: tareaTitulos('reunionCarlos'),
  vendInactive: [],
  coordinador: [],
  directorio: tareaTitulos('llamadaJuan', 'reunionCarlos', 'whatsappAna', 'bandejaLuis', 'bandejaRosa'),
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
  // Un ledger real no se perfora para limpiar tests. Cada corrida usa ids
  // nuevos y al finalizar hace soft-delete; el branch se elimina tras el gate.
  directoryLead: randomUUID(),
  crossTeamLead: randomUUID(),
  directoryActivity: randomUUID(),
  crossTeamActivity: randomUUID(),
  portalClientLead: randomUUID(),
  triggerAssignedInsertLead: randomUUID(),
  triggerSellerChangeLead: randomUUID(),
  triggerSupervisorOnlyLead: randomUUID(),
  triggerNoTenureLead: randomUUID(),
  // C1 — reparto de la cola global (todos nacen sin dueno: ambos-null).
  repartoLeadOk: randomUUID(),
  repartoLeadNoContactar: randomUUID(),
  repartoLeadCarrera: randomUUID(),
  repartoLeadReencolado: randomUUID(),
  repartoTareaReencolada: randomUUID(),
  // C1-bis — descarte de la cola (el codigo marca, el coordinador cierra).
  descarteLeadCredito: randomUUID(),
  descarteLeadLimpio: randomUUID(),
  descarteLeadCarrera: randomUUID(),
  // C1-ter — la vista de descartados (pestaña del coordinador).
  descarteLeadVista: randomUUID(),
  // El reloj del vendedor — tenencia_desde (mide al asesor, no al lead).
  tenenciaLeadViejo: randomUUID(),
  tenenciaLeadPropio: randomUUID(),
  // Avance automatico de etapa: la conversacion sube, el intento no.
  avanceLeadConversacion: randomUUID(),
  avanceLeadIntento: randomUUID(),
  avanceLeadManual: randomUUID(),
  // C1 de la auditoria: lead de la COLA GLOBAL, el vector de escalada.
  avanceLeadColaGlobal: randomUUID(),
  avanceLeadReunion: randomUUID(),
  foreignCreatorTarea: randomUUID(),
  directoryTarea: randomUUID(),
  portalClientTarea: randomUUID(),
  rpcCloseTarea: randomUUID(),
  taskFollowLead: randomUUID(),
  taskFollowTarea: randomUUID(),
  // Anular con autoria + retroceso de etapa (20260726151751).
  anularLead: randomUUID(),
  anularTareaReunion: randomUUID(),
  anularTareaLlamada: randomUUID(),
  anularLeadSistema: randomUUID(),
  anularTareaSistema: randomUUID(),
  // La anulacion AJENA: el supervisor anula la tarea de su vendedor
  // (20260727032429). Lead propio para no contaminar los conteos de arriba.
  anularLeadAjena: randomUUID(),
  anularTareaAjena: randomUUID(),
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
  unique(TAREAS.map((tarea) => tarea.key), 'tarea.key');
  unique(TAREAS.map((tarea) => tarea.id), 'tarea.id');
  unique(TAREAS.map((tarea) => tarea.titulo), 'tarea.titulo');
  unique(Object.values(TRANSIENT_IDS), 'TRANSIENT_IDS');

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
    if (
      !Number.isFinite(lead.estimatedAmount)
      || lead.estimatedAmount <= 0
      || lead.estimatedAmount > 9_999_999_999.99
      || Math.round(lead.estimatedAmount * 100) / 100 !== lead.estimatedAmount
    ) {
      throw new Error(`Fixtures invalidos: capital estimado invalido para ${lead.key}.`);
    }
    if (lead.currency !== 'PEN' && lead.currency !== 'USD') {
      throw new Error(`Fixtures invalidos: moneda invalida para ${lead.key}.`);
    }
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

  const TAREA_TIPOS_VALIDOS = new Set(['llamada', 'whatsapp', 'reunion', 'tarea']);
  for (const tarea of TAREAS) {
    if (!LEAD_BY_KEY[tarea.leadKey]) {
      throw new Error(`Fixtures invalidos: lead inexistente para la tarea ${tarea.key}.`);
    }
    if (!TAREA_TIPOS_VALIDOS.has(tarea.tipo)) {
      throw new Error(`Fixtures invalidos: tipo de tarea invalido para ${tarea.key}.`);
    }
    const titulo = String(tarea.titulo ?? '').trim();
    if (titulo.length < 1 || titulo.length > 200) {
      throw new Error(`Fixtures invalidos: titulo fuera del CHECK para ${tarea.key}.`);
    }
    // Espejo del CHECK tareas_vence_en_cuerda: fecha fija dentro de [2026, 2100).
    const venceEn = Date.parse(tarea.venceEn);
    if (
      !Number.isFinite(venceEn)
      || venceEn < Date.parse('2026-01-01T00:00:00Z')
      || venceEn >= Date.parse('2100-01-01T00:00:00Z')
    ) {
      throw new Error(`Fixtures invalidos: vence_en fuera del CHECK para ${tarea.key}.`);
    }
    if (tarea.estado !== 'pendiente') {
      throw new Error(`Fixtures invalidos: la tarea ${tarea.key} debe nacer pendiente.`);
    }
  }

  const matrixKeys = Object.keys(EXPECTED_LEAD_NAMES).sort();
  const sessionKeys = USERS.map((user) => user.key).sort();
  if (JSON.stringify(matrixKeys) !== JSON.stringify(sessionKeys)) {
    throw new Error('Fixtures invalidos: la matriz no cubre exactamente todos los usuarios demo.');
  }
  const tareaMatrixKeys = Object.keys(EXPECTED_TAREA_TITULOS).sort();
  if (JSON.stringify(tareaMatrixKeys) !== JSON.stringify(sessionKeys)) {
    throw new Error('Fixtures invalidos: la matriz de tareas no cubre exactamente todos los usuarios demo.');
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

  // Un lead es visible para el usuario segun la jerarquia recomputada; la tarea
  // hereda EXACTAMENTE esa visibilidad porque su tenencia se deriva del lead.
  const leadVisibleFor = (user, lead, visibleOwners) => {
    if (user.crmRole === 'gerencia') return true;
    if (lead.sellerKey) return visibleOwners.has(lead.sellerKey);
    return lead.supervisorKey ? visibleOwners.has(lead.supervisorKey) : false;
  };

  for (const user of USERS) {
    let expected = [];
    let expectedTareas = [];
    if (user.portalRole === 'directorio') {
      expected = LEADS.map((lead) => lead.name);
      expectedTareas = TAREAS.map((tarea) => tarea.titulo);
    } else if (user.crmRole && user.crmActive) {
      const visibleOwners = user.crmRole === 'gerencia'
        ? new Set(USERS.filter((candidate) => candidate.crmRole).map((candidate) => candidate.key))
        : descendantsOf(user.key);
      expected = LEADS
        .filter((lead) => leadVisibleFor(user, lead, visibleOwners))
        .map((lead) => lead.name);
      expectedTareas = TAREAS
        .filter((tarea) => leadVisibleFor(user, LEAD_BY_KEY[tarea.leadKey], visibleOwners))
        .map((tarea) => tarea.titulo);
    }
    const declared = [...EXPECTED_LEAD_NAMES[user.key]].sort();
    if (JSON.stringify(expected.sort()) !== JSON.stringify(declared)) {
      throw new Error(`Fixtures invalidos: matriz incoherente para ${user.key}.`);
    }
    const declaredTareas = [...EXPECTED_TAREA_TITULOS[user.key]].sort();
    if (JSON.stringify(expectedTareas.sort()) !== JSON.stringify(declaredTareas)) {
      throw new Error(`Fixtures invalidos: matriz de tareas incoherente para ${user.key}.`);
    }
  }
}
