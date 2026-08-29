#!/usr/bin/env node

// Gate de dos sesiones para tarea de cliente vs. reasignacion de cartera.
// Ambas operaciones hacen COMMIT para probar visibilidad entre backends; por
// eso se niega a correr salvo en una DB PostgreSQL LOCAL y desechable. Cada
// escenario crea su propio cliente de sonda y lo elimina en el `finally`.

import { randomUUID } from 'node:crypto';
import { spawn } from 'node:child_process';
import { performance } from 'node:perf_hooks';
import process from 'node:process';

const rawDatabaseUrl = process.env.TEST_DATABASE_URL;
const disposableAck = process.env.GCAR_LOCAL_DISPOSABLE;
const psqlBin = 'psql';
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function failSafety(message) {
  console.error(`SEGURIDAD: ${message}`);
  process.exit(2);
}

if (!rawDatabaseUrl) {
  failSafety('falta TEST_DATABASE_URL.');
}
if (disposableAck !== '1') {
  failSafety('define GCAR_LOCAL_DISPOSABLE=1 para confirmar que la DB local puede desecharse.');
}

let parsedUrl;
try {
  parsedUrl = new URL(rawDatabaseUrl);
} catch {
  failSafety('TEST_DATABASE_URL no es una URL PostgreSQL valida.');
}

if (!['postgres:', 'postgresql:'].includes(parsedUrl.protocol)) {
  failSafety('TEST_DATABASE_URL debe usar postgres:// o postgresql://.');
}
if (rawDatabaseUrl.includes('?') || rawDatabaseUrl.includes('#')) {
  failSafety('TEST_DATABASE_URL no admite query ni hash.');
}

const urlHostname = parsedUrl.hostname;
if (!['127.0.0.1', 'localhost', '::1', '[::1]'].includes(urlHostname)) {
  failSafety(`host no local rechazado: ${urlHostname}.`);
}
const databaseHost = ['::1', '[::1]'].includes(urlHostname) ? '::1' : urlHostname;

if (!/^\d{1,5}$/.test(parsedUrl.port)) {
  failSafety('TEST_DATABASE_URL debe declarar un puerto numerico explicito.');
}
const databasePort = Number(parsedUrl.port);
if (!Number.isInteger(databasePort) || databasePort < 1 || databasePort > 65535) {
  failSafety(`puerto PostgreSQL invalido: ${parsedUrl.port}.`);
}

let databaseUser;
let databasePassword;
let databaseName;
try {
  databaseUser = decodeURIComponent(parsedUrl.username);
  databasePassword = decodeURIComponent(parsedUrl.password);
  databaseName = decodeURIComponent(parsedUrl.pathname.replace(/^\//, ''));
} catch {
  failSafety('TEST_DATABASE_URL contiene percent-encoding invalido.');
}

if (databaseUser !== 'postgres') {
  failSafety(`usuario local no permitido: ${databaseUser || '(vacio)'}.`);
}
if (!databasePassword) {
  failSafety('TEST_DATABASE_URL debe incluir password para pasarlo solo por PGPASSWORD.');
}

const disposableNameShape = /^gcar(?:[_-][a-z0-9]+)+$/i;
const databaseTokens = databaseName.toLowerCase().split(/[_-]/).slice(1);
const forbiddenDatabaseTokens = new Set(['canonical', 'live', 'main', 'prod', 'production']);
if (!disposableNameShape.test(databaseName)
    || !databaseTokens.some((token) => ['fix', 'test', 'tmp', 'local'].includes(token))
    || databaseTokens.some((token) => forbiddenDatabaseTokens.has(token))) {
  failSafety(
    `nombre de DB no reconocible como gcar desechable con token fix|test|tmp|local: ${databaseName || '(vacio)'}.`,
  );
}

const connection = Object.freeze({
  host: databaseHost,
  port: databasePort,
  user: databaseUser,
  password: databasePassword,
  database: databaseName,
});

function sqlLiteral(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function asError(error) {
  return error instanceof Error ? error : new Error(String(error));
}

function appendError(primary, label, error) {
  const next = asError(error);
  return primary
    ? new Error(`${primary.message}\n${label}: ${next.message}`)
    : new Error(`${label}: ${next.message}`);
}

function isUuid(value) {
  return typeof value === 'string' && uuidPattern.test(value);
}

function isLocalNetworkAddress(value) {
  if (!value) return true;
  const address = String(value).split('/')[0];
  return ['127.0.0.1', '::1'].includes(address)
    || /^(?:10\.|192\.168\.|172\.(?:1[6-9]|2\d|3[01])\.)/.test(address);
}

function assertInternalApplicationName(applicationName) {
  if (!/^gcar_task_[0-9a-f]{32}_(?:s1|s2|ctl)$/.test(applicationName)) {
    throw new Error(`application_name interno invalido: ${applicationName}`);
  }
}

function createChildEnvironment(applicationName) {
  assertInternalApplicationName(applicationName);
  const childEnvironment = { ...process.env };
  for (const key of Object.keys(childEnvironment)) {
    if (key.startsWith('PG') || key === 'TEST_DATABASE_URL') {
      delete childEnvironment[key];
    }
  }
  Object.assign(childEnvironment, {
    PGPASSWORD: connection.password,
    PGAPPNAME: applicationName,
    PGCONNECT_TIMEOUT: '5',
    PGSSLMODE: 'disable',
    PGOPTIONS: [
      '-c statement_timeout=20000',
      '-c lock_timeout=10000',
      '-c idle_in_transaction_session_timeout=25000',
    ].join(' '),
  });
  return childEnvironment;
}

function startPsql(label, sql, applicationName) {
  const child = spawn(
    psqlBin,
    [
      '--host', connection.host,
      '--port', String(connection.port),
      '--username', connection.user,
      '--dbname', connection.database,
      '-X',
      '-v', 'ON_ERROR_STOP=1',
      '-qAt',
      '-c', sql,
    ],
    {
      stdio: ['ignore', 'pipe', 'pipe'],
      env: createChildEnvironment(applicationName),
    },
  );

  let stdout = '';
  let stderr = '';
  let exited = false;
  child.stdout.on('data', (chunk) => { stdout += chunk; });
  child.stderr.on('data', (chunk) => { stderr += chunk; });

  const completion = new Promise((resolve, reject) => {
    child.on('error', (error) => {
      exited = true;
      reject(new Error(`${label}: ${error.message}`));
    });
    child.on('close', (code) => {
      exited = true;
      if (code === 0) {
        resolve(stdout.trim());
        return;
      }
      reject(new Error(`${label}: psql termino ${code}\n${stderr || stdout}`));
    });
  });
  void completion.catch(() => {});

  return {
    applicationName,
    backendPid: null,
    child,
    completion,
    hasExited: () => exited,
  };
}

async function runPsql(label, sql, controllerApplicationName) {
  return startPsql(label, sql, controllerApplicationName).completion;
}

const sleep = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));

function parseBackendRows(output, expectedApplicationName) {
  if (!output) return [];
  return output.split('\n').map((row) => {
    const [
      pidText,
      applicationName,
      serverDatabase,
      serverUser,
      backendType,
      clientAddress,
      state,
      waitEventType,
      waitEvent,
      blockingPidsText,
      ...extra
    ] = row.split('|');
    const pid = Number(pidText);
    const blockingPids = blockingPidsText
      ? blockingPidsText.split(',').map((blockingPid) => Number(blockingPid))
      : [];
    if (!Number.isInteger(pid) || pid < 1 || extra.length > 0
        || blockingPids.some((blockingPid) => !Number.isInteger(blockingPid) || blockingPid < 1)
        || applicationName !== expectedApplicationName
        || serverDatabase !== connection.database
        || serverUser !== connection.user
        || backendType !== 'client backend'
        || !isLocalNetworkAddress(clientAddress)) {
      throw new Error(`identidad de backend no reconocida: ${row}`);
    }
    return {
      pid,
      applicationName,
      serverDatabase,
      serverUser,
      backendType,
      clientAddress,
      state,
      waitEventType,
      waitEvent,
      blockingPids,
    };
  });
}

async function readTrackedBackends(session, controllerApplicationName, label) {
  const output = await runPsql(label, `
    select
      activity.pid::text || '|' ||
      activity.application_name || '|' ||
      activity.datname || '|' ||
      activity.usename || '|' ||
      activity.backend_type || '|' ||
      coalesce(activity.client_addr::text, '') || '|' ||
      activity.state || '|' ||
      coalesce(activity.wait_event_type, '') || '|' ||
      coalesce(activity.wait_event, '') || '|' ||
      coalesce(pg_catalog.array_to_string(pg_catalog.pg_blocking_pids(activity.pid), ','), '')
    from pg_catalog.pg_stat_activity activity
    where activity.application_name = ${sqlLiteral(session.applicationName)}
      and activity.datname = ${sqlLiteral(connection.database)}
      and activity.usename = ${sqlLiteral(connection.user)}
      and activity.backend_type = 'client backend'
      and activity.pid <> pg_catalog.pg_backend_pid()
    order by activity.pid;
  `, controllerApplicationName);
  const rows = parseBackendRows(output, session.applicationName);
  if (rows.length > 1) {
    throw new Error(`${label}: application_name ambiguo (${rows.map((row) => row.pid).join(', ')})`);
  }
  if (rows.length === 1) {
    if (session.backendPid !== null && session.backendPid !== rows[0].pid) {
      throw new Error(
        `${label}: el backend cambio de PID ${session.backendPid} a ${rows[0].pid}`,
      );
    }
    session.backendPid = rows[0].pid;
  }
  return rows;
}

async function waitForBackendState({
  label,
  session,
  controllerApplicationName,
  expectedWaitEventType,
  expectedWaitEvent,
  expectedBlockerPid,
}) {
  const deadline = performance.now() + 8000;
  while (performance.now() < deadline) {
    if (session.hasExited()) {
      await session.completion;
      throw new Error(`${label}: la sesion termino antes del estado esperado`);
    }
    const rows = await readTrackedBackends(
      session,
      controllerApplicationName,
      `observar ${label}`,
    );
    const backend = rows[0];
    if (backend
        && backend.state === 'active'
        && backend.waitEventType === expectedWaitEventType
        && (!expectedWaitEvent || backend.waitEvent === expectedWaitEvent)
        && (!expectedBlockerPid || backend.blockingPids.includes(expectedBlockerPid))) {
      return backend.pid;
    }
    await sleep(100);
  }
  throw new Error(`${label}: estado no observado dentro de 8 s`);
}

async function terminateTrackedSession(session, controllerApplicationName) {
  const deadline = performance.now() + 8000;
  const terminatedPids = new Set();
  while (performance.now() < deadline) {
    const rows = await readTrackedBackends(
      session,
      controllerApplicationName,
      `resolver backend ${session.applicationName}`,
    );
    const backend = rows[0];
    if (!backend) {
      if (session.backendPid !== null || session.hasExited()) return terminatedPids.size;
      await sleep(100);
      continue;
    }

    const output = await runPsql('terminar backend rastreado', `
      select
        activity.pid::text || '|' ||
        activity.application_name || '|' ||
        activity.datname || '|' ||
        activity.usename || '|' ||
        activity.backend_type || '|' ||
        pg_catalog.pg_terminate_backend(activity.pid)::text
      from pg_catalog.pg_stat_activity activity
      where activity.pid = ${backend.pid}
        and activity.application_name = ${sqlLiteral(session.applicationName)}
        and activity.datname = ${sqlLiteral(connection.database)}
        and activity.usename = ${sqlLiteral(connection.user)}
        and activity.backend_type = 'client backend';
    `, controllerApplicationName);
    if (!output) {
      await sleep(100);
      continue;
    }
    const [pidText, appName, serverDb, serverUser, backendType, terminated, ...extra] =
      output.split('|');
    if (Number(pidText) !== backend.pid
        || appName !== session.applicationName
        || serverDb !== connection.database
        || serverUser !== connection.user
        || backendType !== 'client backend'
        || !['true', 'false'].includes(terminated)
        || extra.length > 0) {
      throw new Error(`respuesta de terminacion no reconocida: ${output}`);
    }
    if (terminated === 'true') terminatedPids.add(backend.pid);
    await sleep(100);
  }
  throw new Error(
    `backend ${session.backendPid || '(sin PID)'} / ${session.applicationName} sigue activo tras 8 s`,
  );
}

async function terminateTrackedSessions(sessions, controllerApplicationName) {
  let terminated = 0;
  for (const session of sessions) {
    terminated += await terminateTrackedSession(session, controllerApplicationName);
  }
  return terminated;
}

function parseJsonObject(raw, label) {
  let value;
  try {
    value = JSON.parse(raw);
  } catch {
    throw new Error(`${label}: JSON invalido: ${raw || '(sin filas)'}`);
  }
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error(`${label}: se esperaba un objeto JSON`);
  }
  return value;
}

function countsEqual(left, right) {
  return ['auth_users', 'profiles', 'tasks', 'client_activities', 'audit'].every(
    (key) => Number.isInteger(left?.[key]) && left[key] === right?.[key],
  );
}

function countsText(counts) {
  return [
    counts.auth_users,
    counts.profiles,
    counts.tasks,
    counts.client_activities,
    counts.audit,
  ].join('|');
}

async function loadContext(probe, controllerApplicationName) {
  const raw = await runPsql('preflight local', `
    select pg_catalog.jsonb_build_object(
      'database', pg_catalog.current_database(),
      'server_address', coalesce(pg_catalog.inet_server_addr()::text, ''),
      'client_address', coalesce(pg_catalog.inet_client_addr()::text, ''),
      'server_user', current_user,
      'backend_type', activity.backend_type,
      'application_name', activity.application_name,
      'started_at', pg_catalog.clock_timestamp(),
      'manager_id', gerencia.id,
      'old_analyst_id', analista_anterior.id,
      'old_supervisor_id', supervisor_anterior.id,
      'new_analyst_id', analista_nuevo.id,
      'new_supervisor_id', supervisor_nuevo.id,
      'trigger_locks_rows', (
        trigger_tarea.prosrc ilike '%from public.perfiles p%for share%'
        and trigger_tarea.prosrc ilike '%from crm.equipo e%for share%'
      ),
      'reassignment_trigger_enabled', exists (
        select 1
        from pg_catalog.pg_trigger trigger
        where trigger.tgrelid = 'public.perfiles'::pg_catalog.regclass
          and trigger.tgname = 'trg_perfiles_cliente_reasigna_tareas'
          and trigger.tgenabled = 'O'
      ),
      'probe_ids_free',
        not exists (select 1 from auth.users u where u.id = ${sqlLiteral(probe.clientId)}::uuid)
        and not exists (
          select 1 from public.perfiles p
          where p.id = ${sqlLiteral(probe.clientId)}::uuid
             or p.correo = ${sqlLiteral(probe.email)}
        )
        and not exists (select 1 from crm.tareas t where t.id = ${sqlLiteral(probe.taskId)}::uuid),
      'counts', pg_catalog.jsonb_build_object(
        'auth_users', (select count(*) from auth.users),
        'profiles', (select count(*) from public.perfiles),
        'tasks', (select count(*) from crm.tareas),
        'client_activities', (select count(*) from crm.actividades_cliente),
        'audit', (select count(*) from public.audit_log)
      )
    )::text
    from public.perfiles gerencia
    join crm.equipo equipo_gerencia
      on equipo_gerencia.perfil_id = gerencia.id
    cross join public.perfiles analista_anterior
    join crm.equipo equipo_anterior
      on equipo_anterior.perfil_id = analista_anterior.id
    join public.perfiles supervisor_anterior
      on supervisor_anterior.id = equipo_anterior.supervisor_id
    cross join public.perfiles analista_nuevo
    join crm.equipo equipo_nuevo
      on equipo_nuevo.perfil_id = analista_nuevo.id
    join public.perfiles supervisor_nuevo
      on supervisor_nuevo.id = equipo_nuevo.supervisor_id
    cross join pg_catalog.pg_proc trigger_tarea
    join pg_catalog.pg_stat_activity activity
      on activity.pid = pg_catalog.pg_backend_pid()
    where gerencia.correo = 'gerencia.crm@demo.avancecorp.pe'
      and gerencia.activo and equipo_gerencia.activo
      and equipo_gerencia.rol_crm = 'gerencia'
      and analista_anterior.correo = 'vend1.crm@demo.avancecorp.pe'
      and analista_anterior.activo and equipo_anterior.activo
      and equipo_anterior.rol_crm = 'vendedor'
      and supervisor_anterior.correo = 'sup1.crm@demo.avancecorp.pe'
      and supervisor_anterior.activo
      and analista_nuevo.correo = 'vend3.crm@demo.avancecorp.pe'
      and analista_nuevo.activo and equipo_nuevo.activo
      and equipo_nuevo.rol_crm = 'vendedor'
      and supervisor_nuevo.correo = 'sup2.crm@demo.avancecorp.pe'
      and supervisor_nuevo.activo
      and trigger_tarea.oid = 'private.trg_tareas_before_insert()'::pg_catalog.regprocedure;
  `, controllerApplicationName);
  const value = parseJsonObject(raw, 'preflight');

  if (value.database !== connection.database
      || value.server_user !== connection.user
      || value.backend_type !== 'client backend'
      || value.application_name !== controllerApplicationName) {
    throw new Error(
      `identidad del servidor/control no coincide: ${value.database}|${value.server_user}`
      + `|${value.backend_type}|${value.application_name}`,
    );
  }
  if (!isLocalNetworkAddress(value.server_address)
      || !isLocalNetworkAddress(value.client_address)) {
    throw new Error(
      `servidor/cliente fuera de loopback o bridge local: ${value.server_address}|${value.client_address}`,
    );
  }
  for (const key of [
    'manager_id',
    'old_analyst_id',
    'old_supervisor_id',
    'new_analyst_id',
    'new_supervisor_id',
  ]) {
    if (!isUuid(value[key])) throw new Error(`fixture incompleto: ${key}`);
  }
  if (value.old_analyst_id === value.new_analyst_id
      || value.old_supervisor_id === value.new_supervisor_id) {
    throw new Error('los arboles anterior y nuevo no son distintos');
  }
  if (value.trigger_locks_rows !== true
      || value.reassignment_trigger_enabled !== true
      || value.probe_ids_free !== true) {
    throw new Error('preflight estructural incompleto o IDs de sonda ocupados');
  }
  if (!value.started_at || !countsEqual(value.counts, value.counts)) {
    throw new Error('preflight no devolvio instante o conteos validos');
  }

  return {
    startedAt: value.started_at,
    managerId: value.manager_id,
    oldAnalystId: value.old_analyst_id,
    oldSupervisorId: value.old_supervisor_id,
    newAnalystId: value.new_analyst_id,
    newSupervisorId: value.new_supervisor_id,
    baselineCounts: value.counts,
  };
}

async function createProbe(context, probe, controllerApplicationName) {
  const raw = await runPsql('crear cliente de sonda aislado', `
    begin;
    set local session_replication_role = replica;
    insert into auth.users (
      id, aud, role, email, raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at, is_sso_user, is_anonymous
    ) values (
      ${sqlLiteral(probe.clientId)}::uuid,
      'authenticated',
      'authenticated',
      ${sqlLiteral(probe.email)},
      pg_catalog.jsonb_build_object(
        'provider', 'email', 'providers', pg_catalog.jsonb_build_array('email')
      ),
      pg_catalog.jsonb_build_object('nombre_completo', ${sqlLiteral(probe.name)}),
      pg_catalog.clock_timestamp(),
      pg_catalog.clock_timestamp(),
      false,
      false
    );
    insert into public.perfiles (
      id, nombre_completo, correo, rol, activo, creado_en, actualizado_en,
      creado_por, asesor_perfil_id
    ) values (
      ${sqlLiteral(probe.clientId)}::uuid,
      ${sqlLiteral(probe.name)},
      ${sqlLiteral(probe.email)},
      'cliente',
      true,
      pg_catalog.clock_timestamp(),
      pg_catalog.clock_timestamp(),
      ${sqlLiteral(context.managerId)}::uuid,
      ${sqlLiteral(context.oldAnalystId)}::uuid
    );
    set local session_replication_role = origin;
    select pg_catalog.jsonb_build_object(
      'client_ok', exists (
        select 1
        from public.perfiles p
        where p.id = ${sqlLiteral(probe.clientId)}::uuid
          and p.correo = ${sqlLiteral(probe.email)}
          and p.rol = 'cliente'
          and p.activo
          and p.asesor_perfil_id = ${sqlLiteral(context.oldAnalystId)}::uuid
      ),
      'auth_ok', exists (
        select 1 from auth.users u
        where u.id = ${sqlLiteral(probe.clientId)}::uuid
          and u.email = ${sqlLiteral(probe.email)}
      ),
      'pending_tasks', (
        select count(*) from crm.tareas t
        where t.perfil_id = ${sqlLiteral(probe.clientId)}::uuid
          and t.activo and t.estado = 'pendiente'
      ),
      'counts', pg_catalog.jsonb_build_object(
        'auth_users', (select count(*) from auth.users),
        'profiles', (select count(*) from public.perfiles),
        'tasks', (select count(*) from crm.tareas),
        'client_activities', (select count(*) from crm.actividades_cliente),
        'audit', (select count(*) from public.audit_log)
      )
    )::text;
    commit;
  `, controllerApplicationName);
  const value = parseJsonObject(raw, 'setup de sonda');
  const expectedCounts = {
    ...context.baselineCounts,
    auth_users: context.baselineCounts.auth_users + 1,
    profiles: context.baselineCounts.profiles + 1,
  };
  if (value.client_ok !== true
      || value.auth_ok !== true
      || value.pending_tasks !== 0
      || !countsEqual(value.counts, expectedCounts)) {
    throw new Error(`setup de sonda inesperado: ${raw}`);
  }
}

function insertTaskSql({
  applicationName,
  probe,
  analystId,
  title,
}) {
  return `
    begin;
    set local application_name = ${sqlLiteral(applicationName)};
    set local lock_timeout = '10s';
    set local statement_timeout = '20s';
    select pg_catalog.set_config(
      'request.jwt.claims', '{"role":"authenticated"}', true
    );
    select pg_catalog.set_config(
      'request.jwt.claim.sub', ${sqlLiteral(analystId)}, true
    );
    set local role authenticated;
    with inserted as (
      insert into crm.tareas (
        id, perfil_id, creado_por, tipo, titulo, vence_en
      ) values (
        ${sqlLiteral(probe.taskId)}::uuid,
        ${sqlLiteral(probe.clientId)}::uuid,
        auth.uid(),
        'tarea',
        ${sqlLiteral(title)},
        pg_catalog.now() + interval '1 day'
      )
      returning id, vendedor_id, asignado_supervisor_id
    )
    select pg_catalog.concat_ws(
      '|', 'S1', pg_catalog.pg_backend_pid()::text,
      id::text, vendedor_id::text, asignado_supervisor_id::text
    )
    from inserted;
    select pg_catalog.pg_sleep(5);
    commit;
  `;
}

function reassignClientSql({
  applicationName,
  probe,
  oldAnalystId,
  newAnalystId,
  managerId,
}) {
  return `
    begin;
    set local application_name = ${sqlLiteral(applicationName)};
    set local lock_timeout = '10s';
    set local statement_timeout = '20s';
    select pg_catalog.set_config(
      'request.jwt.claims', '{"role":"authenticated"}', true
    );
    select pg_catalog.set_config(
      'request.jwt.claim.sub', ${sqlLiteral(managerId)}, true
    );
    with moved as (
      update public.perfiles profile
         set asesor_perfil_id = ${sqlLiteral(newAnalystId)}::uuid
       where profile.id = ${sqlLiteral(probe.clientId)}::uuid
         and profile.correo = ${sqlLiteral(probe.email)}
         and profile.asesor_perfil_id = ${sqlLiteral(oldAnalystId)}::uuid
      returning profile.id, profile.asesor_perfil_id
    )
    select pg_catalog.concat_ws(
      '|', 'S2', pg_catalog.pg_backend_pid()::text,
      id::text, asesor_perfil_id::text
    )
    from moved;
    commit;
  `;
}

async function cleanupScenario(context, probe, controllerApplicationName) {
  const raw = await runPsql('cleanup aislado y conteos globales', `
    begin;
    set local session_replication_role = replica;

    do $cleanup_guard$
    begin
      if exists (
        select 1
        from auth.users user_row
        where user_row.id = ${sqlLiteral(probe.clientId)}::uuid
          and user_row.email is distinct from ${sqlLiteral(probe.email)}
      ) then
        raise exception 'cleanup: el auth user UUID propio ya no conserva su identidad';
      end if;
      if exists (
        select 1
        from public.perfiles profile
        where profile.id = ${sqlLiteral(probe.clientId)}::uuid
          and not (
            profile.correo = ${sqlLiteral(probe.email)}
            and profile.nombre_completo = ${sqlLiteral(probe.name)}
            and profile.rol = 'cliente'
            and profile.creado_por = ${sqlLiteral(context.managerId)}::uuid
            and profile.asesor_perfil_id in (
              ${sqlLiteral(context.oldAnalystId)}::uuid,
              ${sqlLiteral(context.newAnalystId)}::uuid
            )
          )
      ) then
        raise exception 'cleanup: el perfil UUID propio recibio una mutacion ajena';
      end if;
      if exists (
        select 1
        from crm.tareas task
        where task.perfil_id = ${sqlLiteral(probe.clientId)}::uuid
          and task.id <> ${sqlLiteral(probe.taskId)}::uuid
      ) then
        raise exception 'cleanup: aparecio una tarea ajena sobre el perfil de sonda';
      end if;
      if exists (
        select 1
        from crm.tareas task
        where task.id = ${sqlLiteral(probe.taskId)}::uuid
          and not (
            task.perfil_id = ${sqlLiteral(probe.clientId)}::uuid
            and task.titulo = ${sqlLiteral(probe.title)}
            and task.creado_por = ${sqlLiteral(context.oldAnalystId)}::uuid
            and task.estado = 'pendiente'
            and task.activo
            and (
              (
                task.vendedor_id = ${sqlLiteral(context.oldAnalystId)}::uuid
                and task.asignado_supervisor_id = ${sqlLiteral(context.oldSupervisorId)}::uuid
              )
              or (
                task.vendedor_id = ${sqlLiteral(context.newAnalystId)}::uuid
                and task.asignado_supervisor_id = ${sqlLiteral(context.newSupervisorId)}::uuid
              )
            )
          )
      ) then
        raise exception 'cleanup: la tarea UUID propia recibio una mutacion ajena';
      end if;
      if exists (
        select 1
        from crm.actividades_cliente activity
        where activity.cliente_id = ${sqlLiteral(probe.clientId)}::uuid
          and not (
            activity.tipo = 'reasignacion'
            and activity.creado_por = ${sqlLiteral(context.managerId)}::uuid
            and activity.creado_en >= ${sqlLiteral(context.startedAt)}::timestamptz
          )
      ) then
        raise exception 'cleanup: aparecio una actividad ajena sobre el perfil de sonda';
      end if;
    end;
    $cleanup_guard$;

    create temporary table gcar_task_probe_activities on commit drop as
    select activity.id
    from crm.actividades_cliente activity
    where activity.cliente_id = ${sqlLiteral(probe.clientId)}::uuid;

    create temporary table gcar_task_probe_audit on commit drop as
    select audit.id
    from public.audit_log audit
    where (
      audit.ts >= ${sqlLiteral(context.startedAt)}::timestamptz
      and audit.fila_id in (
          ${sqlLiteral(probe.clientId)},
          ${sqlLiteral(probe.taskId)}
        )
      )
      or audit.fila_id in (
        select activity.id::text from gcar_task_probe_activities activity
      );

    delete from public.audit_log audit
    where audit.id in (select target.id from gcar_task_probe_audit target);

    delete from crm.tareas task
    where task.id = ${sqlLiteral(probe.taskId)}::uuid
      and task.perfil_id = ${sqlLiteral(probe.clientId)}::uuid
      and task.titulo = ${sqlLiteral(probe.title)};

    delete from crm.actividades_cliente activity
    where activity.id in (select target.id from gcar_task_probe_activities target);

    delete from public.perfiles profile
    where profile.id = ${sqlLiteral(probe.clientId)}::uuid
      and profile.correo = ${sqlLiteral(probe.email)}
      and profile.nombre_completo = ${sqlLiteral(probe.name)}
      and profile.rol = 'cliente';

    delete from auth.users user_row
    where user_row.id = ${sqlLiteral(probe.clientId)}::uuid
      and user_row.email = ${sqlLiteral(probe.email)}
      and not exists (
        select 1 from public.perfiles profile
        where profile.id = ${sqlLiteral(probe.clientId)}::uuid
      );

    set local session_replication_role = origin;
    select pg_catalog.jsonb_build_object(
      'residues', pg_catalog.jsonb_build_object(
        'auth_user', (
          select count(*) from auth.users u
          where u.id = ${sqlLiteral(probe.clientId)}::uuid
             or u.email = ${sqlLiteral(probe.email)}
        ),
        'profile', (
          select count(*) from public.perfiles p
          where p.id = ${sqlLiteral(probe.clientId)}::uuid
             or p.correo = ${sqlLiteral(probe.email)}
        ),
        'task', (
          select count(*) from crm.tareas t
          where t.id = ${sqlLiteral(probe.taskId)}::uuid
        ),
        'client_activities', (
          select count(*) from crm.actividades_cliente activity
          where activity.id in (select target.id from gcar_task_probe_activities target)
             or activity.cliente_id = ${sqlLiteral(probe.clientId)}::uuid
        ),
        'audit', (
          select count(*) from public.audit_log audit
          where audit.id in (select target.id from gcar_task_probe_audit target)
             or (
               audit.ts >= ${sqlLiteral(context.startedAt)}::timestamptz
               and audit.fila_id in (
                 ${sqlLiteral(probe.clientId)},
                 ${sqlLiteral(probe.taskId)}
               )
             )
        )
      ),
      'counts', pg_catalog.jsonb_build_object(
        'auth_users', (select count(*) from auth.users),
        'profiles', (select count(*) from public.perfiles),
        'tasks', (select count(*) from crm.tareas),
        'client_activities', (select count(*) from crm.actividades_cliente),
        'audit', (select count(*) from public.audit_log)
      )
    )::text;
    commit;
  `, controllerApplicationName);
  const value = parseJsonObject(raw, 'cleanup');
  const noResidues = value.residues
    && Object.values(value.residues).every((count) => count === 0);
  if (!noResidues) {
    throw new Error(`cleanup dejo residuos propios: ${JSON.stringify(value.residues)}`);
  }
  if (!countsEqual(value.counts, context.baselineCounts)) {
    throw new Error(
      'conteos globales cambiaron; no se borro ni restauro trabajo ajeno: '
      + `${countsText(context.baselineCounts)} -> ${countsText(value.counts)}`,
    );
  }
  return countsText(value.counts);
}

async function runScenario({ injectFailure }) {
  const runId = randomUUID();
  const compactRunId = runId.replaceAll('-', '');
  const controllerApplicationName = `gcar_task_${compactRunId}_ctl`;
  const appSession1 = `gcar_task_${compactRunId}_s1`;
  const appSession2 = `gcar_task_${compactRunId}_s2`;
  const probe = {
    clientId: randomUUID(),
    taskId: randomUUID(),
    email: `gcar-task-${compactRunId}@probe.invalid`,
    name: `CLIENTE SONDA GCAR ${compactRunId.toUpperCase()}`,
    title: `GCAR CONCURRENCIA ANALISTA ${runId}`,
  };
  const injectedFailureMessage = 'fallo inyectado con ambas sesiones rastreadas';
  let context;
  let session1;
  let session2;
  let primaryError;
  let expectedFailureObserved = false;
  let terminatedBackends = 0;
  let result;
  let cleanupCounts;

  try {
    context = await loadContext(probe, controllerApplicationName);
    await createProbe(context, probe, controllerApplicationName);

    session1 = startPsql(
      'sesion 1: alta de tarea',
      insertTaskSql({
        applicationName: appSession1,
        probe,
        analystId: context.oldAnalystId,
        title: probe.title,
      }),
      appSession1,
    );
    await waitForBackendState({
      label: 'sesion 1 reteniendo locks',
      session: session1,
      controllerApplicationName,
      expectedWaitEventType: 'Timeout',
      expectedWaitEvent: 'PgSleep',
    });

    const secondStartedAt = performance.now();
    let secondFinishedAt;
    session2 = startPsql(
      'sesion 2: reasignacion',
      reassignClientSql({
        applicationName: appSession2,
        probe,
        oldAnalystId: context.oldAnalystId,
        newAnalystId: context.newAnalystId,
        managerId: context.managerId,
      }),
      appSession2,
    );
    const timedSecondCompletion = session2.completion.then((output) => {
      secondFinishedAt = performance.now();
      return output;
    });
    void timedSecondCompletion.catch(() => {});

    await waitForBackendState({
      label: 'sesion 2 esperando el row-lock',
      session: session2,
      controllerApplicationName,
      expectedWaitEventType: 'Lock',
      expectedBlockerPid: session1.backendPid,
    });

    if (injectFailure) {
      expectedFailureObserved = true;
      throw new Error(injectedFailureMessage);
    }

    const [session1Output, session2Output] = await Promise.all([
      session1.completion,
      timedSecondCompletion,
    ]);
    const secondElapsedMs = Math.round(secondFinishedAt - secondStartedAt);

    const initial = session1Output.match(
      /S1\|(\d+)\|([0-9a-f-]{36})\|([0-9a-f-]{36})\|([0-9a-f-]{36})/i,
    );
    const reassigned = session2Output.match(
      /S2\|(\d+)\|([0-9a-f-]{36})\|([0-9a-f-]{36})/i,
    );
    if (!initial || !reassigned) {
      throw new Error(`salida no reconocida: S1=${session1Output} S2=${session2Output}`);
    }
    if (Number(initial[1]) !== session1.backendPid
        || initial[2] !== probe.taskId
        || initial[3] !== context.oldAnalystId
        || initial[4] !== context.oldSupervisorId) {
      throw new Error(`sesion/destino inicial no canonico: ${initial.slice(1).join('|')}`);
    }
    if (Number(reassigned[1]) !== session2.backendPid
        || reassigned[2] !== probe.clientId
        || reassigned[3] !== context.newAnalystId) {
      throw new Error(`sesion/reasignacion no canonica: ${reassigned.slice(1).join('|')}`);
    }
    if (secondElapsedMs < 1800) {
      throw new Error(`la reasignacion no espero el lock de la tarea (${secondElapsedMs} ms)`);
    }

    const finalState = await runPsql('verificar destino final', `
      select pg_catalog.concat_ws(
        '|', task.id::text, task.estado, task.vendedor_id::text,
        task.asignado_supervisor_id::text, profile.asesor_perfil_id::text
      )
      from crm.tareas task
      join public.perfiles profile on profile.id = task.perfil_id
      where task.id = ${sqlLiteral(probe.taskId)}::uuid
        and task.perfil_id = ${sqlLiteral(probe.clientId)}::uuid
        and task.titulo = ${sqlLiteral(probe.title)}
        and task.activo;
    `, controllerApplicationName);
    const [finalTaskId, finalStatus, finalAnalystId, finalSupervisorId, finalClientAnalyst] =
      finalState.split('|');
    if (finalTaskId !== probe.taskId
        || finalStatus !== 'pendiente'
        || finalAnalystId !== context.newAnalystId
        || finalSupervisorId !== context.newSupervisorId
        || finalClientAnalyst !== context.newAnalystId) {
      throw new Error(`estado final no canonico: ${finalState}`);
    }

    result = {
      oldAnalystId: context.oldAnalystId,
      oldSupervisorId: context.oldSupervisorId,
      newAnalystId: context.newAnalystId,
      newSupervisorId: context.newSupervisorId,
      secondElapsedMs,
    };
  } catch (error) {
    const current = asError(error);
    const expected = injectFailure
      && expectedFailureObserved
      && current.message === injectedFailureMessage;
    if (!expected) primaryError = current;
  } finally {
    // Primero el waiter y luego quien sostiene el lock: evita que S2 alcance a
    // commitear mientras se termina S1 en una ruta de error.
    const sessions = [session2, session1].filter(Boolean);
    try {
      terminatedBackends += await terminateTrackedSessions(
        sessions,
        controllerApplicationName,
      );
    } catch (error) {
      primaryError = appendError(primaryError, 'Terminacion exacta fallo', error);
    }

    for (const session of sessions) {
      if (!session.hasExited()) session.child.kill('SIGTERM');
    }
    await Promise.allSettled(sessions.map((session) => session.completion));

    try {
      terminatedBackends += await terminateTrackedSessions(
        sessions,
        controllerApplicationName,
      );
    } catch (error) {
      primaryError = appendError(primaryError, 'Postcondicion de sesiones fallo', error);
    }

    if (context) {
      try {
        cleanupCounts = await cleanupScenario(context, probe, controllerApplicationName);
      } catch (error) {
        primaryError = appendError(primaryError, 'Cleanup aislado fallo', error);
      }
    }
  }

  if (injectFailure && !expectedFailureObserved) {
    primaryError = appendError(
      primaryError,
      'Fallo inyectado no observado',
      'las dos sesiones no alcanzaron los estados esperados',
    );
  }
  if (injectFailure && terminatedBackends < 2) {
    primaryError = appendError(
      primaryError,
      'Fallo inyectado no termino ambos backends',
      `pg_terminate_backend confirmo ${terminatedBackends}/2`,
    );
  }
  if (primaryError) throw primaryError;
  return { result, cleanupCounts };
}

try {
  const injected = await runScenario({ injectFailure: true });
  console.log('TAREAS_CLIENTE_CONCURRENCIA_FALLO_INYECTADO_CLEANUP_OK');
  console.log(`Conteos estables tras falla auth|perfiles|tareas|actividades|audit: ${injected.cleanupCounts}`);

  const positive = await runScenario({ injectFailure: false });
  console.log('TAREAS_CLIENTE_CONCURRENCIA_LOCAL_OK');
  console.log(
    `Destino: Analista anterior/supervisor ${positive.result.oldAnalystId}`
      + `/${positive.result.oldSupervisorId} -> ${positive.result.newAnalystId}`
      + `/${positive.result.newSupervisorId}; espera S2: ${positive.result.secondElapsedMs} ms.`,
  );
  console.log(
    `TAREAS_CLIENTE_CONCURRENCIA_CONTEOS_ESTABLES_OK ${positive.cleanupCounts}`,
  );
} catch (error) {
  console.error(asError(error).message);
  process.exitCode = 1;
}
