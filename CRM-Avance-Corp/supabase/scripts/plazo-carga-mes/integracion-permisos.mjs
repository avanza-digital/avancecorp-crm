// Gate focal del plazo de carga por mes (20261015000852): Auth real, PostgREST real y ESCRITURAS reales.
// Solo contra un banco LOCAL propio (127.0.0.1); nunca la referencia productiva. Crea sus actores sintéticos por la
// API de administración de Auth, fija un plazo de verdad con la sesión de Gerencia y lo limpia todo al terminar.
//
//   PLAZO_API_URL=http://127.0.0.1:<puerto api> PLAZO_DB_URL=postgresql://postgres:postgres@127.0.0.1:<puerto db>/postgres \
//   PLAZO_ANON_KEY=… PLAZO_SERVICE_ROLE_KEY=… node supabase/scripts/test-rls.mjs --plazo-carga-mes
//
// Las llaves salen de `supabase status --workdir <stack> -o env` (las del stack local; no se imprimen).
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { randomBytes, randomUUID } from 'node:crypto';

const url = process.env.PLAZO_API_URL ?? '';
const anon = process.env.PLAZO_ANON_KEY ?? '';
const servicio = process.env.PLAZO_SERVICE_ROLE_KEY ?? '';
const db = new URL(process.env.PLAZO_DB_URL ?? 'postgresql://invalido');
assert(url && anon && servicio, 'Faltan PLAZO_API_URL, PLAZO_ANON_KEY o PLAZO_SERVICE_ROLE_KEY');
assert.equal(new URL(url).hostname, '127.0.0.1', 'Solo un banco local (127.0.0.1)');
assert.equal(db.hostname, '127.0.0.1', 'Solo una base local (127.0.0.1)');
assert(!url.includes('dctqcbznekcyxhjujuci') && !String(db).includes('dctqcbznekcyxhjujuci'), 'PRODUCCIÓN PROHIBIDA');

const q = (v) => (v == null ? 'null' : `'${String(v).replaceAll("'", "''")}'`);
function sql(texto) {
  const env = { ...process.env };
  for (const n of ['PGHOSTADDR', 'PGSERVICE', 'PGSERVICEFILE']) delete env[n];
  Object.assign(env, {
    PGHOST: db.hostname, PGPORT: db.port || '5432', PGDATABASE: db.pathname.slice(1),
    PGUSER: decodeURIComponent(db.username), PGPASSWORD: decodeURIComponent(db.password), PGSSLMODE: 'disable',
  });
  const r = spawnSync(process.env.PSQL_BIN || 'psql', ['-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-f', '-'],
    { env, input: texto, encoding: 'utf8', maxBuffer: 8 * 1024 * 1024 });
  assert.equal(r.status, 0, `SQL del banco: ${r.stderr}`);
  return r.stdout.trim();
}
async function http(ruta, { token = anon, body, method = 'POST', schema } = {}) {
  const r = await fetch(url + ruta, {
    method, signal: AbortSignal.timeout(20000),
    headers: {
      apikey: anon, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json',
      ...(schema ? { 'Content-Profile': schema, 'Accept-Profile': schema } : {}),
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  const texto = await r.text();
  let data; try { data = JSON.parse(texto); } catch { data = texto; }
  return { status: r.status, data };
}
const rpc = (nombre, body, token) => http(`/rest/v1/rpc/${nombre}`, { body, token, schema: 'crm' });

const pruebas = [];
function ok(nombre, condicion, detalle = '') {
  assert(condicion, `${nombre}: ${detalle}`);
  pruebas.push(nombre);
  console.log(`PASS: ${nombre}`);
}

assert.equal(sql("select (to_regprocedure('crm.fijar_plazo_carga_mes(date,date,text)') is not null)::int"), '1',
  'La migración 20261015000852 no está aplicada en este banco');
assert.equal(sql('select (select count(*) from crm.plazos_carga_mes) + (select count(*) from crm.reaperturas_mes)'), '0',
  'El banco ya tiene decisiones o reaperturas: correr en un banco limpio');

const corrida = randomUUID().slice(0, 8);
// Lo que siembra la reapertura por HTTP (para limpiarlo aunque algo falle a mitad).
const tarde = { persona: randomUUID(), cierre: randomUUID(), inversion: randomUUID(), comprobante: randomUUID(), sello: false };
const clave = `Banco-${randomBytes(18).toString('base64url')}`;
const actores = {};
const ids = [];
async function usuario(nombre, rolPortal, rolCrm = null, activo = true, supervisor = null) {
  const email = `plazo.${corrida}.${nombre}@pruebas.example`;
  const alta = await http('/auth/v1/admin/users', { token: servicio, body: { email, password: clave, email_confirm: true } });
  assert([200, 201].includes(alta.status), `Auth alta ${nombre}: ${JSON.stringify(alta.data)}`);
  const id = alta.data.id;
  ids.push(id);
  sql(`insert into public.perfiles (id, nombre_completo, correo, rol, activo, debe_cambiar_password)
       values (${q(id)}, ${q(`PRUEBA PLAZO ${nombre.toUpperCase()}`)}, ${q(email)}, ${q(rolPortal)}, true, false)
       on conflict (id) do update set rol = excluded.rol, nombre_completo = excluded.nombre_completo, activo = true,
         debe_cambiar_password = false;
       ${rolCrm ? `insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo) values (${q(id)}, ${q(rolCrm)}, ${q(supervisor)}, true);` : ''}
       ${rolCrm && !activo ? `update crm.equipo set activo = false where perfil_id = ${q(id)};` : ''}`);
  const login = await http('/auth/v1/token?grant_type=password', { body: { email, password: clave } });
  assert.equal(login.status, 200, `Auth debe entregar una sesión real (${nombre})`);
  return { id, token: login.data.access_token };
}

const hoyLima = sql("select (now() at time zone 'America/Lima')::date");
const mesAnterior = sql("select (date_trunc('month', now() at time zone 'America/Lima') - interval '1 month')::date");
const ultimoDia = sql("select ((now() at time zone 'America/Lima')::date + 5)");
const args = { p_periodo: mesAnterior, p_ultimo_dia: ultimoDia, p_motivo: 'Prueba HTTP del plazo de carga' };

try {
  actores.gerencia = await usuario('gerencia', 'comercial', 'gerencia');
  actores.supervisor = await usuario('supervisor', 'comercial', 'supervisor');
  actores.vendedor = await usuario('vendedor', 'comercial', 'vendedor', true, actores.supervisor.id);
  actores.coordinador = await usuario('coordinador', 'comercial', 'coordinador');
  actores.directorio = await usuario('directorio', 'directorio', 'directorio');
  actores.gerenciaBaja = await usuario('gerencia_baja', 'comercial', 'gerencia', false);
  actores.adminPortal = await usuario('admin_portal', 'admin');
  actores.superadmin = await usuario('superadmin', 'superadmin');
  actores.cliente = await usuario('cliente', 'cliente');
  actores.anon = { token: anon };
  actores.servicio = { token: servicio };
  // El mes anterior con metas publicadas: así es el mes pendiente del aviso de cierre (como septiembre hoy).
  sql(`insert into crm.meta_periodos (periodo, revision, publicada_en, publicada_por)
       values (${q(mesAnterior)}, 1, now(), ${q(actores.gerencia.id)})`);
  const antes = await rpc('cierre_mes_estado_fn', {}, actores.vendedor.token);
  ok('antes de decidir, el aviso de cierre muestra la fecha base (día 11 del mes siguiente)',
    antes.status === 200 && antes.data?.pendiente?.mes === mesAnterior.slice(0, 7)
      && antes.data?.pendiente?.cierra_el === sql(`select (${q(mesAnterior)}::date + interval '1 month 10 days')::date`),
    JSON.stringify(antes.data));

  // Las dos tablas nunca se leen por la Data API (ni siquiera Gerencia).
  for (const tabla of ['plazos_carga_mes', 'reaperturas_mes']) {
    for (const nombre of ['gerencia', 'vendedor', 'anon', 'servicio']) {
      const r = await http(`/rest/v1/${tabla}?select=*&limit=1`, { method: 'GET', token: actores[nombre].token, schema: 'crm' });
      ok(`${nombre} no lee crm.${tabla} por la API`, [401, 403].includes(r.status) && r.data?.code === '42501',
        JSON.stringify(r));
    }
  }

  // Denegados: todos menos Gerencia activa, con 42501 y sin escribir.
  for (const nombre of ['supervisor', 'vendedor', 'coordinador', 'directorio', 'gerenciaBaja', 'adminPortal', 'superadmin',
    'cliente', 'anon', 'servicio']) {
    const f = await rpc('fijar_plazo_carga_mes', args, actores[nombre].token);
    ok(`${nombre}: fijar el plazo → 42501`, [401, 403].includes(f.status) && f.data?.code === '42501', JSON.stringify(f));
    const l = await rpc('plazos_carga_mes_fn', {}, actores[nombre].token);
    ok(`${nombre}: leer los plazos → 42501`, [401, 403].includes(l.status) && l.data?.code === '42501', JSON.stringify(l));
  }
  ok('ningún denegado escribió', sql('select count(*) from crm.plazos_carga_mes') === '0');

  // Gerencia: lee (igual que el SQL con su identidad) y fija un plazo de verdad.
  const lectura = await rpc('plazos_carga_mes_fn', {}, actores.gerencia.token);
  ok('gerencia lee los plazos', lectura.status === 200 && lectura.data?.version === 1 && lectura.data?.hoy === hoyLima,
    JSON.stringify(lectura));
  const porSql = JSON.parse(sql(`begin;
    select set_config('request.jwt.claim.sub', ${q(actores.gerencia.id)}, true),
           set_config('request.jwt.claims', json_build_object('sub', ${q(actores.gerencia.id)}, 'role', 'authenticated')::text, true) \\g /dev/null
    select crm.plazos_carga_mes_fn() - 'generado_en';
    rollback;`).split('\n').filter((l) => l.startsWith('{')).pop());
  const { generado_en: _g, ...sinHora } = lectura.data;
  ok('la lectura por HTTP es la misma que por SQL (salvo la hora)', JSON.stringify(sinHora) === JSON.stringify(porSql));

  const malo = await rpc('fijar_plazo_carga_mes', { ...args, p_motivo: 'abc' }, actores.gerencia.token);
  ok('gerencia: motivo corto → 400 con 22023 y mensaje de negocio',
    malo.status === 400 && malo.data?.code === '22023' && /motivo debe tener entre 5 y 300/.test(malo.data?.message ?? ''),
    JSON.stringify(malo));
  const bien = await rpc('fijar_plazo_carga_mes', args, actores.gerencia.token);
  ok('gerencia fija el plazo del mes anterior', bien.status === 200 && bien.data?.ok === true && bien.data?.reabierto === false
    && bien.data?.mes === mesAnterior.slice(0, 7) && bien.data?.ultimo_dia === ultimoDia, JSON.stringify(bien));
  ok('la decisión queda con el actor de la sesión (no un parámetro)',
    sql(`select count(*) from crm.plazos_carga_mes where decidido_por = ${q(actores.gerencia.id)} and periodo = ${q(mesAnterior)}
         and ultimo_dia = ${q(ultimoDia)} and motivo = 'Prueba HTTP del plazo de carga'`) === '1');
  const despues = await rpc('plazos_carga_mes_fn', {}, actores.gerencia.token);
  const mes = (despues.data?.meses ?? []).find((m) => m.mes === mesAnterior.slice(0, 7));
  ok('la lectura muestra el plazo nuevo y quién lo decidió', mes?.plazo_ultimo_dia === ultimoDia && mes?.ampliado === true
    && mes?.decision?.decidido_por === 'PRUEBA PLAZO GERENCIA', JSON.stringify(mes));
  const aviso = await rpc('cierre_mes_estado_fn', {}, actores.vendedor.token);
  const avisoAntes = antes;
  ok('el aviso de cierre (de un analista) refleja el plazo nuevo sin cambiar su forma',
    aviso.status === 200 && aviso.data?.pendiente?.mes === mesAnterior.slice(0, 7)
      && aviso.data?.pendiente?.cierra_el === sql(`select (${q(ultimoDia)}::date + 1)`)
      && aviso.data?.pendiente?.estado === 'en_ventana'
      && JSON.stringify(Object.keys(aviso.data).sort()) === JSON.stringify(Object.keys(avisoAntes.data).sort()),
    JSON.stringify(aviso.data));

  // ── Reapertura por HTTP: el mes anterior SELLADO (como septiembre el 11/10) con una venta en cooperativa del mes
  //    registrada tarde (imputada a hoy, con su rastro) de un analista con meta. Siembra con los disparadores apagados.
  tarde.sello = true;
  sql(`begin;
    set local session_replication_role = replica;
    insert into crm.metas_vendedor (meta_periodo_id, vendedor_id, supervisor_id, conversion_objetivo)
      select mp.id, ${q(actores.vendedor.id)}, ${q(actores.supervisor.id)}, 10 from crm.meta_periodos mp where mp.periodo = ${q(mesAnterior)};
    insert into crm.periodos_cerrados (periodo, cerrado_en, automatico, ponderacion_referido, meta_revision, cobertura)
      values (${q(mesAnterior)}, now() - interval '3 days', true, 0.15, 1, '{}'::jsonb);
    insert into crm.cierre_mes_vendedor (periodo, vendedor_id, nombre_completo, supervisor_id, supervisor_nombre, divisor,
      cierres_no_referidos, cierres_referidos, cierres_de_arrastre, numerador, estado, referidos_recibidos,
      referidos_dados_de_alta, conversion_objetivo)
      values (${q(mesAnterior)}, ${q(actores.vendedor.id)}, 'PRUEBA PLAZO VENDEDOR', ${q(actores.supervisor.id)},
              'PRUEBA PLAZO SUPERVISOR', 10, 1, 0, 0, 1, 'sellado', 0, 0, 10);
    insert into crm.inversionistas (id, estado) values (${q(tarde.persona)}, 'activo');
    insert into storage.objects (id, bucket_id, name) values (${q(tarde.comprobante)}, 'prueba-plazo', ${q('plazo-http/' + corrida)});
    insert into crm.cierres_externos (id, cooperativa, monto, moneda, documento_tipo, documento, nombre_completo,
      numero_transaccion, vendedor_id, creado_por, inversionista_id, es_cierre_inicial, fecha_comercial, fecha_imputacion,
      comprobante_objeto_id, referencia_externa)
      values (${q(tarde.cierre)}, 'qorilazo', 20000, 'PEN', 'DNI', '75000001', 'CLIENTE HTTP PLAZO', ${q('OP-HTTP-' + corrida)},
              ${q(actores.vendedor.id)}, ${q(actores.vendedor.id)}, ${q(tarde.persona)}, false,
              ${q(mesAnterior)}::date + 14, ${q(hoyLima)}::date, ${q(tarde.comprobante)}, ${q('REF-' + corrida)});
    insert into crm.inversiones (id, inversionista_id, empresa_id, cierre_externo_id, estado, fecha_comercial)
      values (${q(tarde.inversion)}, ${q(tarde.persona)}, gen_random_uuid(), ${q(tarde.cierre)}, 'vigente', ${q(mesAnterior)}::date + 14);
    insert into crm.inversion_ajustes_mes_cerrado (inversion_id, periodo_origen, fecha_imputacion, creado_por)
      values (${q(tarde.inversion)}, ${q(mesAnterior)}, ${q(hoyLima)}, ${q(actores.gerencia.id)});
    commit;`);
  const sellado = await rpc('plazos_carga_mes_fn', {}, actores.gerencia.token);
  const mesSellado = (sellado.data?.meses ?? []).find((m) => m.mes === mesAnterior.slice(0, 7));
  ok('la lectura ofrece reabrir el mes anterior sellado', mesSellado?.sellado === true && mesSellado?.reabrible === true
    && mesSellado?.motivo_no_reabrible === null, JSON.stringify(mesSellado));
  const negado = await rpc('fijar_plazo_carga_mes', { ...args, p_motivo: 'Reapertura sin permiso' }, actores.supervisor.token);
  ok('supervisión no reabre (42501) y el sello sigue', [401, 403].includes(negado.status) && negado.data?.code === '42501'
    && sql(`select count(*) from crm.periodos_cerrados where periodo = ${q(mesAnterior)}`) === '1', JSON.stringify(negado));
  const reab = await rpc('fijar_plazo_carga_mes', { ...args, p_motivo: 'Reapertura HTTP de prueba' }, actores.gerencia.token);
  ok('gerencia reabre el mes anterior por la API', reab.status === 200 && reab.data?.reabierto === true
    && typeof reab.data?.reapertura_id === 'string' && reab.data?.ventas_devueltas?.length === 1
    && Number(reab.data.ventas_devueltas[0].monto) === 20000 && reab.data.ventas_devueltas[0].imputada_antes_a === hoyLima,
  JSON.stringify(reab));
  ok('el sello, la foto y el rastro se retiraron y la venta volvió a su mes',
    sql(`select (select count(*) from crm.periodos_cerrados where periodo = ${q(mesAnterior)})
              + (select count(*) from crm.cierre_mes_vendedor where periodo = ${q(mesAnterior)})
              + (select count(*) from crm.inversion_ajustes_mes_cerrado where inversion_id = ${q(tarde.inversion)})`) === '0'
    && sql(`select (fecha_imputacion = fecha_comercial)::text from crm.cierres_externos where id = ${q(tarde.cierre)}`) === 'true');
  ok('la reapertura queda a nombre de la sesión de Gerencia, con su llave y sin datos del cliente',
    sql(`select count(*) from crm.reaperturas_mes where id = ${q(reab.data?.reapertura_id)} and decidido_por = ${q(actores.gerencia.id)}
          and strpos(respaldo::text, '75000001') = 0`) === '1');
} finally {
  // Limpieza: lo de esta corrida, con los candados apagados SOLO para borrar historia de prueba de un banco local.
  if (ids.length) {
    const lista = ids.map(q).join(',');
    sql(`begin;
      set local session_replication_role = replica;
      delete from public.audit_log where usuario_id in (${lista})
         or fila_id in (select id::text from crm.plazos_carga_mes where decidido_por in (${lista}))
         or fila_id in (select id::text from crm.reaperturas_mes where decidido_por in (${lista}))
         or (tabla in ('perfiles', 'public.perfiles', 'crm.equipo') and fila_id in (select x::text from unnest(array[${lista}]::uuid[]) x));
      delete from crm.inversion_ajustes_mes_cerrado where inversion_id = ${q(tarde.inversion)};
      delete from crm.inversiones where id = ${q(tarde.inversion)};
      delete from public.audit_log where fila_id in (${q(tarde.cierre)}, ${q(tarde.inversion)});
      delete from crm.cierres_externos where id = ${q(tarde.cierre)};
      delete from storage.objects where id = ${q(tarde.comprobante)};
      delete from crm.inversionistas where id = ${q(tarde.persona)};
      ${tarde.sello ? `delete from crm.cierre_mes_vendedor where periodo = ${q(mesAnterior)};
      delete from crm.periodos_cerrados where periodo = ${q(mesAnterior)};` : ''}
      delete from crm.metas_vendedor where vendedor_id in (${lista});
      delete from public.audit_log where tabla = 'crm.meta_periodos'
         and fila_id in (select id::text from crm.meta_periodos where publicada_por in (${lista}));
      delete from crm.meta_periodos where publicada_por in (${lista});
      delete from crm.plazos_carga_mes where decidido_por in (${lista});
      delete from crm.reaperturas_mes where decidido_por in (${lista});
      delete from crm.equipo where perfil_id in (${lista});
      delete from public.perfiles where id in (${lista});
      commit;`);
    for (const id of ids) await http(`/auth/v1/admin/users/${id}`, { method: 'DELETE', token: servicio });
  }
}
console.log(`PASS: ${pruebas.length} aserciones del plazo de carga con Auth y PostgREST reales (banco local).`);
