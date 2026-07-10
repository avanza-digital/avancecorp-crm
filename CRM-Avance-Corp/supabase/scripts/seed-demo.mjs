// seed-demo.mjs — usuarios y datos demo del CRM para un BRANCH de Supabase.
// ⚠️ SOLO contra un branch/staging. Aborta si el ref es el de producción.
// Uso: SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... node seed-demo.mjs
//
// Crea: 1 gerencia, 2 supervisores, 4 vendedores (2 por supervisor) y 1 directorio
// (este último solo perfil del portal, NO se enrola en crm.equipo), + 6 leads demo.

import { createClient } from '@supabase/supabase-js';

const URL = process.env.SUPABASE_URL;
const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!URL || !KEY) { console.error('Faltan SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY'); process.exit(1); }
if (URL.includes('dctqcbznekcyxhjujuci')) {
  console.error('⛔ Este es el ref de PRODUCCIÓN. El seed demo solo corre en branches.');
  process.exit(1);
}

const admin = createClient(URL, KEY);
const PASS = 'demo-crm-2026'; // password compartida SOLO demo/branch

const USUARIOS = [
  { correo: 'gerencia.crm@demo.avancecorp.pe',   nombre: 'GERENCIA DEMO',    rol_crm: 'gerencia',   sup: null },
  { correo: 'sup1.crm@demo.avancecorp.pe',       nombre: 'SUPERVISOR UNO',   rol_crm: 'supervisor', sup: null },
  { correo: 'sup2.crm@demo.avancecorp.pe',       nombre: 'SUPERVISOR DOS',   rol_crm: 'supervisor', sup: null },
  { correo: 'vend1.crm@demo.avancecorp.pe',      nombre: 'VENDEDOR UNO',     rol_crm: 'vendedor',   sup: 'sup1.crm@demo.avancecorp.pe' },
  { correo: 'vend2.crm@demo.avancecorp.pe',      nombre: 'VENDEDOR DOS',     rol_crm: 'vendedor',   sup: 'sup1.crm@demo.avancecorp.pe' },
  { correo: 'vend3.crm@demo.avancecorp.pe',      nombre: 'VENDEDOR TRES',    rol_crm: 'vendedor',   sup: 'sup2.crm@demo.avancecorp.pe' },
  { correo: 'vend4.crm@demo.avancecorp.pe',      nombre: 'VENDEDOR CUATRO',  rol_crm: 'vendedor',   sup: 'sup2.crm@demo.avancecorp.pe' },
  { correo: 'directorio.crm@demo.avancecorp.pe', nombre: 'DIRECTORIO DEMO',  rol_crm: null,         sup: null, rol_portal: 'directorio' },
];

const ids = {}; // correo → uuid

async function crearUsuario(u) {
  const { data, error } = await admin.auth.admin.createUser({
    email: u.correo, password: PASS, email_confirm: true,
  });
  let id = data?.user?.id;
  if (error) {
    if (!String(error.message).match(/already/i)) throw error;
    const { data: lista } = await admin.auth.admin.listUsers({ perPage: 1000 });
    id = lista.users.find((x) => x.email === u.correo)?.id;
  }
  ids[u.correo] = id;

  // Perfil del portal (rol analista para la fuerza comercial; directorio para el lector)
  const { error: e2 } = await admin.from('perfiles').upsert({
    id,
    correo: u.correo,
    nombre_completo: u.nombre,
    rol: u.rol_portal ?? 'analista',
    activo: true,
  }, { onConflict: 'id' });
  if (e2) throw e2;
}

async function main() {
  for (const u of USUARIOS) await crearUsuario(u);
  console.log('✓ usuarios y perfiles creados');

  // Enrolar en crm.equipo (orden: gerencia y supervisores primero por la auto-FK)
  for (const u of USUARIOS.filter((x) => x.rol_crm)) {
    const { error } = await admin.schema('crm').from('equipo').upsert({
      perfil_id: ids[u.correo],
      rol_crm: u.rol_crm,
      supervisor_id: u.sup ? ids[u.sup] : null,
      activo: true,
    }, { onConflict: 'perfil_id' });
    if (error) throw error;
  }
  console.log('✓ crm.equipo enrolado (1 gerencia, 2 supervisores, 4 vendedores)');

  const LEADS = [
    { nombre_completo: 'JUAN PEREZ DEMO',   telefono: '987654321', vendedor: 'vend1.crm@demo.avancecorp.pe', etapa: 'nuevo',              monto_estimado: 15000, moneda: 'PEN' },
    { nombre_completo: 'MARIA LOPEZ DEMO',  telefono: '987654322', vendedor: 'vend1.crm@demo.avancecorp.pe', etapa: 'contactado',         monto_estimado: 30000, moneda: 'PEN' },
    { nombre_completo: 'CARLOS RUIZ DEMO',  telefono: '987654323', vendedor: 'vend2.crm@demo.avancecorp.pe', etapa: 'reunion_agendada',   monto_estimado: 10000, moneda: 'USD' },
    { nombre_completo: 'ANA TORRES DEMO',   telefono: '987654324', vendedor: 'vend3.crm@demo.avancecorp.pe', etapa: 'propuesta_enviada',  monto_estimado: 50000, moneda: 'PEN' },
    { nombre_completo: 'LUIS GARCIA DEMO',  telefono: '987654325', vendedor: null, supervisor: 'sup1.crm@demo.avancecorp.pe', etapa: 'nuevo' }, // parkeado
    { nombre_completo: 'ROSA DIAZ DEMO',    telefono: '987654326', vendedor: null, supervisor: 'sup2.crm@demo.avancecorp.pe', etapa: 'nuevo' }, // parkeado
  ];
  for (const l of LEADS) {
    const { error } = await admin.schema('crm').from('leads').insert({
      nombre_completo: l.nombre_completo,
      telefono: l.telefono,
      origen: 'oficina',
      etapa: l.etapa,
      monto_estimado: l.monto_estimado ?? null,
      moneda: l.moneda ?? 'PEN',
      vendedor_id: l.vendedor ? ids[l.vendedor] : null,
      asignado_supervisor_id: l.supervisor ? ids[l.supervisor] : null,
      creado_por: ids['gerencia.crm@demo.avancecorp.pe'],
    });
    if (error && !String(error.message).match(/duplicate|unique/i)) throw error;
  }
  console.log('✓ 6 leads demo (4 asignados + 2 parkeados)');
  console.log(`\nListo. Password demo: ${PASS}`);
}

main().catch((e) => { console.error('✗', e.message ?? e); process.exit(1); });
