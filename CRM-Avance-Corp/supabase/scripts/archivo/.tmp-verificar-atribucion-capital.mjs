// Diagnóstico de SOLO LECTURA (no escribe nada): compara, para los contratos
// del mes en curso ligados a un cliente nacido de un lead del CRM, si
// `contratos.creado_por` (quien registró el contrato) coincide con
// `crm.leads.vendedor_id` (quien de verdad trabajó ese lead).
//
// Objetivo: cuantificar el impacto real del hallazgo — que
// `private.produccion_mes_por_vendedor` (la que alimenta crm.cumplimiento_metas_fn,
// el ranking "Capital confirmado" y el % de avance de meta) atribuye TODO el
// capital por `creado_por` porque `crm.leads.contrato_id` nunca se puebla —
// antes de tocar ninguna migración.
//
// Uso:
//   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... node verificar-atribucion-capital.mjs [--periodo=YYYY-MM-01]

import { createClient } from '@supabase/supabase-js';

const ARGS = process.argv.slice(2);
const periodoArg = ARGS.find((a) => a.startsWith('--periodo='))?.split('=')[1];

const SUPABASE_URL = process.env.SUPABASE_URL?.trim();
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY?.trim();

function fatal(msg) {
  process.stderr.write(`✗ ${msg}\n`);
  process.exit(2);
}
if (!SUPABASE_URL) fatal('Falta SUPABASE_URL.');
if (!SERVICE_KEY) fatal('Falta SUPABASE_SERVICE_ROLE_KEY.');
if (SUPABASE_URL.includes('<') || SERVICE_KEY.includes('<')) {
  fatal('SUPABASE_URL o SUPABASE_SERVICE_ROLE_KEY todavía tienen el placeholder "<...>" sin reemplazar.');
}

const hoy = new Date();
const inicioMes = periodoArg ?? `${hoy.getUTCFullYear()}-${String(hoy.getUTCMonth() + 1).padStart(2, '0')}-01`;

const crm = createClient(SUPABASE_URL, SERVICE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
  db: { schema: 'crm' },
});
const pub = createClient(SUPABASE_URL, SERVICE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
  db: { schema: 'public' },
});

async function paginar(cliente, tabla, columnas, filtro) {
  const filas = [];
  const pageSize = 1000;
  let desde = 0;
  for (;;) {
    let q = cliente.from(tabla).select(columnas).range(desde, desde + pageSize - 1);
    if (filtro) q = filtro(q);
    const { data, error } = await q;
    if (error) throw error;
    filas.push(...data);
    if (data.length < pageSize) break;
    desde += pageSize;
  }
  return filas;
}

async function main() {
  // 0. ¿Sigue siendo cierto que crm.leads.contrato_id nunca se puebla?
  const { count: enlacesVivos, error: e0 } = await crm
    .from('leads')
    .select('id', { count: 'exact', head: true })
    .not('contrato_id', 'is', null);
  if (e0) throw e0;

  // 1. Leads con perfil_id (nacidos en clientes) — id, vendedor_id, perfil_id.
  const leads = await paginar(crm, 'leads', 'id,vendedor_id,perfil_id', (q) => q.not('perfil_id', 'is', null));
  const vendedorPorPerfil = new Map();
  for (const l of leads) {
    if (l.perfil_id == null) continue;
    // Si dos leads comparten perfil con vendedores distintos, se marca ambiguo (null).
    if (vendedorPorPerfil.has(l.perfil_id)) {
      if (vendedorPorPerfil.get(l.perfil_id) !== l.vendedor_id) vendedorPorPerfil.set(l.perfil_id, null);
    } else {
      vendedorPorPerfil.set(l.perfil_id, l.vendedor_id);
    }
  }

  // 2. Contratos del mes en curso (fecha_cierre_comercial) cuyo cliente nació de un lead.
  const finMes = new Date(Date.UTC(
    Number(inicioMes.slice(0, 4)),
    Number(inicioMes.slice(5, 7)),
    1,
  )).toISOString().slice(0, 10);
  const contratos = await paginar(
    pub,
    'contratos',
    'id,creado_por,cliente_id,capital,moneda,categoria,fecha_cierre_comercial',
    (q) => q.gte('fecha_cierre_comercial', inicioMes).lt('fecha_cierre_comercial', finMes),
  );

  let conLead = 0;
  let coinciden = 0;
  let difieren = 0;
  let ambiguos = 0;
  let capitalDifiereePEN = 0;
  let capitalDifiereUSD = 0;
  const ejemplos = [];

  for (const c of contratos) {
    if (!vendedorPorPerfil.has(c.cliente_id)) continue; // no nació de un lead del CRM
    conLead += 1;
    const vendedorReal = vendedorPorPerfil.get(c.cliente_id);
    if (vendedorReal === null) { ambiguos += 1; continue; }
    if (vendedorReal === c.creado_por) {
      coinciden += 1;
    } else {
      difieren += 1;
      if (c.moneda === 'PEN') capitalDifiereePEN += Number(c.capital ?? 0);
      if (c.moneda === 'USD') capitalDifiereUSD += Number(c.capital ?? 0);
      if (ejemplos.length < 10) {
        ejemplos.push({
          contrato: c.id, creado_por: c.creado_por, vendedor_real_del_lead: vendedorReal,
          capital: c.capital, moneda: c.moneda,
        });
      }
    }
  }

  console.log(JSON.stringify({
    periodo: inicioMes,
    enlaces_leads_contrato_id_vivos: enlacesVivos ?? 0,
    contratos_del_periodo: contratos.length,
    contratos_con_cliente_nacido_de_lead: conLead,
    creado_por_coincide_con_vendedor_del_lead: coinciden,
    creado_por_DIFIERE_del_vendedor_del_lead: difieren,
    perfiles_ambiguos_dos_vendedores: ambiguos,
    capital_mal_atribuido_pen: capitalDifiereePEN,
    capital_mal_atribuido_usd: capitalDifiereUSD,
    ejemplos_de_divergencia: ejemplos,
  }, null, 2));
}

main().catch((err) => {
  console.error('✗', err?.message || '(sin mensaje)');
  console.error('detalle:', JSON.stringify(err, Object.getOwnPropertyNames(err ?? {}), 2));
  if (err?.stack) console.error(err.stack);
  process.exit(1);
});
