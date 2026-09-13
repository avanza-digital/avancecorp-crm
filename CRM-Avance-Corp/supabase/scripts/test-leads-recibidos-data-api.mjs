// Verificación remota y autocontenida de crm.leads_recibidos_analista_fn.
// Solo se admite branch/staging. Crea un usuario efímero, prueba la RPC con
// una sesión real y elimina usuario + fixtures aun cuando una aserción falle.

import { execFileSync } from 'node:child_process';
import { randomBytes, randomUUID } from 'node:crypto';

import { createClient } from '@supabase/supabase-js';

import { PRODUCTION_PROJECT_REF } from './fixtures.mjs';

const SUPABASE_URL = process.env.SUPABASE_URL?.trim();
const ANON_KEY = process.env.SUPABASE_ANON_KEY?.trim();
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY?.trim();
const PSQL_URL = process.env.CRM_BANCO_PSQL_URL?.trim();

function exigir(condicion, mensaje) {
  if (!condicion) throw new Error(mensaje);
}

function validarEntorno() {
  exigir(SUPABASE_URL, 'Falta SUPABASE_URL.');
  exigir(ANON_KEY, 'Falta SUPABASE_ANON_KEY.');
  exigir(SERVICE_KEY, 'Falta SUPABASE_SERVICE_ROLE_KEY.');
  exigir(PSQL_URL, 'Falta CRM_BANCO_PSQL_URL.');

  const destino = new URL(SUPABASE_URL);
  exigir(destino.protocol === 'https:', 'SUPABASE_URL debe usar HTTPS.');
  exigir(!SUPABASE_URL.includes(PRODUCTION_PROJECT_REF),
    'Destino de PRODUCCIÓN detectado; esta prueba solo corre en branch/staging.');
}

function ejecutarSql(sql, { devolver = false } = {}) {
  return execFileSync(
    'psql',
    [PSQL_URL, '-X', '-v', 'ON_ERROR_STOP=1', '-qAt', '-c', sql],
    { encoding: devolver ? 'utf8' : undefined, stdio: devolver ? 'pipe' : 'ignore' },
  )?.trim();
}

function fechaLima() {
  return new Intl.DateTimeFormat('en-CA', {
    day: '2-digit',
    month: '2-digit',
    timeZone: 'America/Lima',
    year: 'numeric',
  }).format(new Date());
}

async function main() {
  validarEntorno();

  const sufijo = randomUUID();
  const correo = `oraculo.leads.${sufijo}@example.invalid`;
  const password = `${randomBytes(24).toString('base64url')}aA1!`;
  const leadId = randomUUID();
  const politicaId = randomUUID();
  let usuarioId = null;
  let fallo = null;

  const admin = createClient(SUPABASE_URL, SERVICE_KEY, {
    auth: { autoRefreshToken: false, detectSessionInUrl: false, persistSession: false },
  });
  const anon = createClient(SUPABASE_URL, ANON_KEY, {
    auth: { autoRefreshToken: false, detectSessionInUrl: false, persistSession: false },
  });

  try {
    const alta = await admin.auth.admin.createUser({
      email: correo,
      email_confirm: true,
      password,
    });
    exigir(!alta.error, `No se pudo crear el usuario efímero: ${alta.error?.message}`);
    usuarioId = alta.data.user?.id ?? null;
    exigir(usuarioId, 'Supabase Auth no devolvió el UUID del usuario efímero.');

    ejecutarSql(`
      begin;
      set local session_replication_role = replica;
      insert into public.perfiles (id, nombre_completo, rol, activo, correo)
      values ('${usuarioId}', 'ORACULO DATA API LEADS RECIBIDOS', 'analista', true, '${correo}');
      insert into crm.equipo (perfil_id, rol_crm, activo)
      values ('${usuarioId}', 'vendedor', true);
      insert into crm.leads(id,nombre_completo,telefono,origen,etapa,monto_estimado,
        moneda,vendedor_id,creado_por,creado_en,actualizado_en)
      values('${leadId}','ORACULO DATA API FILTRO','51998112233','otro','nuevo',1000,
        'PEN','${usuarioId}','${usuarioId}',now()-interval '90 days',now());
      insert into crm.lead_asignaciones (
        lead_id, ciclo_n, episodio_n, analista_id, motivo_apertura, asignado_en,
        sla_global_iniciado_en, sla_politica_asignacion_id,
        primera_gestion_limite_en, primer_contacto_limite_en, moneda, origen
      ) values (
        '${leadId}', 1, 1, '${usuarioId}', 'asignado', pg_catalog.now(),
        pg_catalog.now(), '${politicaId}', pg_catalog.now() + interval '1 hour',
        pg_catalog.now() + interval '2 hours', 'PEN', 'oraculo_data_api'
      );
      commit;
    `);

    const sesion = await anon.auth.signInWithPassword({ email: correo, password });
    exigir(!sesion.error, `No se pudo iniciar la sesión efímera: ${sesion.error?.message}`);

    const hoy = fechaLima();
    const respuesta = await anon.schema('crm').rpc('leads_recibidos_analista_fn', {
      p_desde: hoy,
      p_hasta: hoy,
    });
    exigir(!respuesta.error, `La RPC autenticada falló: ${respuesta.error?.code} ${respuesta.error?.message}`);
    exigir(respuesta.data?.version === 1, 'La RPC no devolvió version=1.');
    exigir(respuesta.data?.periodo?.desde === hoy && respuesta.data?.periodo?.hasta === hoy,
      'La RPC no devolvió el periodo solicitado.');
    exigir(respuesta.data?.total === 1, `La RPC devolvió total=${respuesta.data?.total}; se esperaba 1.`);
    exigir(Array.isArray(respuesta.data?.dias) && respuesta.data.dias.length === 1,
      'La RPC no devolvió exactamente un día.');
    exigir(respuesta.data.dias[0]?.fecha === hoy && respuesta.data.dias[0]?.total === 1,
      'El detalle diario de la RPC no coincide con el fixture.');

    const filtrada = await anon.schema('crm').rpc('cartera_filtrada_fn', { p_desde: hoy, p_hasta: hoy });
    exigir(!filtrada.error, `Falló la cartera integrada: ${filtrada.error?.code} ${filtrada.error?.message}`);
    exigir(filtrada.data?.resumen?.totales?.vivos === 1 && filtrada.data?.items?.[0]?.id === leadId,
      'La recepción reciente debe mostrar el lead creado hace 90 días y total=1.');
    exigir(Boolean(filtrada.data.items[0].recibido_en), 'La recepción real no devolvió su fecha.');
    const vacia = await anon.schema('crm').rpc('cartera_filtrada_fn', { p_desde: hoy, p_hasta: hoy, p_etapa: 'descartado' });
    exigir(!vacia.error && vacia.data?.resumen?.totales?.vivos === 0 && vacia.data?.items?.length === 0,
      'El cambio de etapa debe filtrar listado e indicadores juntos.');

    await anon.auth.signOut();
    const sinSesion = createClient(SUPABASE_URL, ANON_KEY, {
      auth: { autoRefreshToken: false, detectSessionInUrl: false, persistSession: false },
    });
    const respuestaAnon = await sinSesion.schema('crm').rpc('leads_recibidos_analista_fn', {
      p_desde: hoy,
      p_hasta: hoy,
    });
    exigir(Boolean(respuestaAnon.error), 'La RPC aceptó una llamada anónima.');
    exigir(
      respuestaAnon.error?.code === '42501'
        || /permission denied|not authorized|no autorizado/i.test(respuestaAnon.error?.message ?? ''),
      `La llamada anónima falló por otra causa: ${respuestaAnon.error?.code} ${respuestaAnon.error?.message}`,
    );
    const filtradaAnon = await sinSesion.schema('crm').rpc('cartera_filtrada_fn', { p_desde: hoy, p_hasta: hoy });
    exigir(filtradaAnon.error?.code === '42501', 'La cartera integrada no rechazó anon con 42501.');
  } catch (error) {
    fallo = error;
  } finally {
    if (usuarioId) {
      try {
        ejecutarSql(`
          begin;
          set local session_replication_role = replica;
          delete from crm.lead_asignaciones where lead_id = '${leadId}';
          delete from crm.leads where id = '${leadId}';
          delete from crm.equipo where perfil_id = '${usuarioId}';
          delete from public.perfiles where id = '${usuarioId}';
          commit;
        `);
      } catch (error) {
        fallo ??= new Error(`Falló la limpieza SQL: ${error?.message ?? String(error)}`);
      }

      const baja = await admin.auth.admin.deleteUser(usuarioId);
      if (baja.error) {
        fallo ??= new Error(`Falló la baja del usuario efímero: ${baja.error.message}`);
      }
    }
  }

  if (fallo) throw fallo;

  const residuos = Number(ejecutarSql(`
    select
      (select pg_catalog.count(*) from crm.lead_asignaciones where lead_id = '${leadId}')
      + (select pg_catalog.count(*) from crm.leads where id = '${leadId}')
      + (select pg_catalog.count(*) from public.perfiles where id = '${usuarioId}')
      + (select pg_catalog.count(*) from crm.equipo where perfil_id = '${usuarioId}');
  `, { devolver: true }));
  exigir(residuos === 0, `La limpieza dejó ${residuos} fila(s) SQL.`);

  console.log('LEADS_RECIBIDOS_DATA_API_OK: recepción y cartera integrada con Auth real, anon=denegado, residuos=0');
}

main().catch((error) => {
  console.error(`LEADS_RECIBIDOS_DATA_API_FAIL: ${error?.message ?? String(error)}`);
  process.exit(1);
});
