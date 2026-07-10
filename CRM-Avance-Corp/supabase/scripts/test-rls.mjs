// test-rls.mjs — suite de RLS del CRM con logins REALES por rol (anon key).
// Es el GATE de cada merge de migraciones. Corre contra un branch con seed-demo.
// Uso: SUPABASE_URL=... SUPABASE_ANON_KEY=... node test-rls.mjs
//
// Verifica (patrón test-rls.mjs de VITANOVA, dimensión tenant→jerarquía):
//   1. gerencia ve TODOS los leads (6); supervisor1 ve los de su subárbol +
//      sus parkeados (3); vendedor1 ve SOLO los suyos (2); directorio ve todo.
//   2. vendedor NO ve leads de otro vendedor ni los del otro supervisor.
//   3. vendedor NO puede reasignar (trigger) ni hard-borrar (sin policy) leads.
//   4. directorio NO puede escribir NADA (insert de lead y de actividad fallan).
//   5. NADIE lee columnas bancarias vía crm.clientes_basicos (no existen en la vista).
//   6. anon no ve nada del esquema crm.

import { createClient } from '@supabase/supabase-js';

const URL = process.env.SUPABASE_URL;
const ANON = process.env.SUPABASE_ANON_KEY;
if (!URL || !ANON) { console.error('Faltan SUPABASE_URL / SUPABASE_ANON_KEY'); process.exit(1); }

const PASS = 'demo-crm-2026';
let fallas = 0;
const ok = (m) => console.log(`  ✓ ${m}`);
const ko = (m) => { console.error(`  ✗ ${m}`); fallas++; };
const check = (cond, m) => (cond ? ok(m) : ko(m));

async function login(correo) {
  const sb = createClient(URL, ANON, { auth: { persistSession: false } });
  const { error } = await sb.auth.signInWithPassword({ email: correo, password: PASS });
  if (error) throw new Error(`login ${correo}: ${error.message}`);
  return sb;
}

async function main() {
  console.log('— RLS CRM: visibilidad jerárquica —');
  const gerencia = await login('gerencia.crm@demo.avancecorp.pe');
  const sup1 = await login('sup1.crm@demo.avancecorp.pe');
  const vend1 = await login('vend1.crm@demo.avancecorp.pe');
  const vend3 = await login('vend3.crm@demo.avancecorp.pe');
  const directorio = await login('directorio.crm@demo.avancecorp.pe');

  const leadsDe = async (sb) => (await sb.schema('crm').from('leads').select('id, nombre_completo, vendedor_id')).data ?? [];

  const lg = await leadsDe(gerencia);
  check(lg.length === 6, `gerencia ve 6 leads (vio ${lg.length})`);

  const ls1 = await leadsDe(sup1);
  check(ls1.length === 3, `supervisor1 ve 3 (2 de su equipo + 1 parkeado suyo; vio ${ls1.length})`);

  const lv1 = await leadsDe(vend1);
  check(lv1.length === 2, `vendedor1 ve solo sus 2 (vio ${lv1.length})`);
  check(!lv1.some((l) => l.nombre_completo.includes('ANA TORRES')), 'vendedor1 NO ve leads de vend3 (otro subárbol)');
  check(!lv1.some((l) => l.vendedor_id === null), 'vendedor1 NO ve leads parkeados');

  const lv3 = await leadsDe(vend3);
  check(lv3.length === 1, `vendedor3 ve solo el suyo (vio ${lv3.length})`);

  const ld = await leadsDe(directorio);
  check(ld.length === 6, `directorio ve TODO en lectura (vio ${ld.length})`);

  console.log('— Escrituras prohibidas —');
  const miLead = lv1[0];
  {
    const { error } = await vend1.schema('crm').from('leads')
      .update({ vendedor_id: lv3[0]?.vendedor_id ?? null }).eq('id', miLead.id);
    check(!!error, `vendedor no puede reasignar (trigger): ${error?.message ?? 'PASÓ SIN ERROR'}`);
  }
  {
    const { error, count } = await vend1.schema('crm').from('leads')
      .delete({ count: 'exact' }).eq('id', miLead.id);
    check(!!error || count === 0, 'vendedor no puede hacer DELETE (sin policy/grant)');
  }
  {
    const { error } = await directorio.schema('crm').from('leads').insert({
      nombre_completo: 'INTRUSO DIRECTORIO', telefono: '999999999',
      creado_por: (await directorio.auth.getUser()).data.user.id,
    });
    check(!!error, `directorio NO inserta leads: ${error?.message ?? 'PASÓ SIN ERROR'}`);
  }
  {
    const { error } = await directorio.schema('crm').from('actividades').insert({
      lead_id: ld[0].id, tipo: 'nota', detalle: 'intruso',
      creado_por: (await directorio.auth.getUser()).data.user.id,
    });
    check(!!error, `directorio NO inserta actividades: ${error?.message ?? 'PASÓ SIN ERROR'}`);
  }
  {
    const { data: acts } = await vend1.schema('crm').from('actividades').select('id').limit(1);
    if (acts?.length) {
      const { error, count } = await vend1.schema('crm').from('actividades')
        .update({ detalle: 'hack' }, { count: 'exact' }).eq('id', acts[0].id);
      check(!!error || count === 0, 'actividades es inmutable (sin UPDATE)');
    } else ok('actividades inmutable (sin filas que probar — se valida por grants)');
  }

  console.log('— Columnas bancarias fuera del alcance del CRM —');
  {
    const { data, error } = await vend1.schema('crm').from('clientes_basicos').select('*').limit(1);
    const cols = data?.[0] ? Object.keys(data[0]) : [];
    const bancarias = cols.filter((c) => /banco|cuenta|cci|beneficiario/i.test(c));
    check(!error && bancarias.length === 0,
      `clientes_basicos sin columnas bancarias (columnas: ${cols.join(', ') || 'sin filas'})`);
  }
  {
    const { error } = await vend1.schema('crm').from('leads').select('id').limit(1);
    check(!error, 'vendedor accede al esquema crm expuesto (sanity)');
  }

  console.log('— anon —');
  {
    const anon = createClient(URL, ANON, { auth: { persistSession: false } });
    const { data, error } = await anon.schema('crm').from('leads').select('id').limit(1);
    check(!!error || (data ?? []).length === 0, 'anon no lee nada de crm');
  }

  console.log(fallas === 0 ? '\n✅ RLS OK — gate aprobado' : `\n❌ ${fallas} fallas — NO mergear`);
  process.exit(fallas === 0 ? 0 : 1);
}

main().catch((e) => { console.error('✗ error fatal:', e.message ?? e); process.exit(1); });
