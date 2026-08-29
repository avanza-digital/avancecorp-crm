#!/usr/bin/env node

// Gate de dos sesiones para la numeración automática de contratos.
// Hace COMMIT para que la segunda sesión observe el correlativo de la primera,
// por eso se niega a correr salvo en una base LOCAL declarada desechable.

import { randomUUID } from 'node:crypto';
import { spawn } from 'node:child_process';
import { performance } from 'node:perf_hooks';
import process from 'node:process';

const databaseUrl = process.env.TEST_DATABASE_URL;
const psqlBin = process.env.PSQL_BIN || 'psql';
const disposableAck = process.env.GCAR_LOCAL_DISPOSABLE;
const controlledPgOptions = '-c statement_timeout=20000 -c lock_timeout=10000';
const controlApplicationName = `gcar_control_${randomUUID().replaceAll('-', '')}`;

function failSafety(message) {
  console.error(`SEGURIDAD: ${message}`);
  process.exit(2);
}

if (!databaseUrl) {
  failSafety('falta TEST_DATABASE_URL.');
}
if (disposableAck !== '1') {
  failSafety('define GCAR_LOCAL_DISPOSABLE=1 para confirmar que la DB local puede desecharse.');
}

let parsedUrl;
try {
  parsedUrl = new URL(databaseUrl);
} catch {
  failSafety('TEST_DATABASE_URL no es una URL PostgreSQL válida.');
}

if (!['postgres:', 'postgresql:'].includes(parsedUrl.protocol)) {
  failSafety('TEST_DATABASE_URL debe usar postgres:// o postgresql://.');
}
if (databaseUrl.includes('?') || databaseUrl.includes('#')
    || parsedUrl.search || parsedUrl.hash) {
  failSafety('TEST_DATABASE_URL no admite query ni fragmento (incluido hostaddr/options).');
}

const urlHostname = parsedUrl.hostname.toLowerCase();
if (!['127.0.0.1', 'localhost', '[::1]'].includes(urlHostname)) {
  failSafety(`host no local rechazado: ${parsedUrl.hostname}.`);
}

let databaseName;
let databaseUser;
let databasePassword;
try {
  databaseName = decodeURIComponent(parsedUrl.pathname.replace(/^\//, ''));
  databaseUser = decodeURIComponent(parsedUrl.username);
  databasePassword = decodeURIComponent(parsedUrl.password);
} catch {
  failSafety('TEST_DATABASE_URL contiene escapes inválidos.');
}

if (!databaseUser) {
  failSafety('TEST_DATABASE_URL debe declarar el usuario PostgreSQL.');
}
if (!databasePassword) {
  failSafety('TEST_DATABASE_URL debe incluir password para pasarlo solo por PGPASSWORD.');
}

// El marcador desechable debe ser un segmento completo. El anclaje impide que
// `foo_gcar_test`, `gcar_preview` o `gcar_local/otra` pasen por coincidencia parcial.
const disposableDatabaseName =
  /^gcar(?:[_-][a-z0-9]+)*[_-](?:fix|test|tmp|local)(?:[_-][a-z0-9]+)*$/;
const forbiddenDatabaseTokens = new Set(['canonical', 'live', 'main', 'prod', 'production']);
const databaseTokens = databaseName.split(/[_-]/);
if (!disposableDatabaseName.test(databaseName)
    || databaseTokens.some((token) => forbiddenDatabaseTokens.has(token))) {
  failSafety(`nombre de DB no reconocible como desechable: ${databaseName || '(vacío)'}.`);
}

const databasePort = parsedUrl.port || '5432';
if (!/^\d{1,5}$/.test(databasePort)
    || Number(databasePort) < 1
    || Number(databasePort) > 65535) {
  failSafety(`puerto PostgreSQL inválido: ${databasePort}.`);
}

const databaseHost = urlHostname === '[::1]' ? '::1' : urlHostname;
const libpqConnectionArgs = [
  '-h', databaseHost,
  '-p', databasePort,
  '-U', databaseUser,
  '-d', databaseName,
  '-w',
];

function childEnvironment(applicationName) {
  const environment = { ...process.env };
  // Ningún PG* heredado puede añadir `hostaddr`, service, options, contraseña o
  // application_name. La conexión se deriva exclusivamente de la URL ya validada.
  for (const key of Object.keys(environment)) {
    if (/^PG[A-Z0-9_]*$/.test(key)) delete environment[key];
  }
  delete environment.TEST_DATABASE_URL;
  delete environment.DATABASE_URL;
  environment.PGPASSWORD = databasePassword;
  environment.PGOPTIONS = controlledPgOptions;
  environment.PGAPPNAME = applicationName;
  environment.PGCONNECT_TIMEOUT = '5';
  environment.PGSSLMODE = 'disable';
  return environment;
}

function sqlLiteral(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function startPsql(label, sql, applicationName) {
  const effectiveApplicationName = applicationName || controlApplicationName;
  if (!/^gcar_(?:control|contrato)_[a-f0-9]{32}(?:_s[12])?$/.test(effectiveApplicationName)) {
    throw new Error(`${label}: application_name interno inválido`);
  }

  const child = spawn(
    psqlBin,
    ['-X', '-v', 'ON_ERROR_STOP=1', '-qAt', ...libpqConnectionArgs, '-c', sql],
    {
      stdio: ['ignore', 'pipe', 'pipe'],
      env: childEnvironment(effectiveApplicationName),
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
      reject(new Error(`${label}: psql terminó ${code}\n${stderr || stdout}`));
    });
  });
  // El `finally` espera todas las sesiones. Este manejador preventivo evita
  // un rechazo no atendido si otra operación falla antes de alcanzar ese punto.
  void completion.catch(() => {});

  return {
    applicationName: effectiveApplicationName,
    backendPid: null,
    child,
    completion,
    hasExited: () => exited,
    stdout: () => stdout.trim(),
  };
}

async function runPsql(label, sql) {
  return startPsql(label, sql).completion;
}

const sleep = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));

function createContractSql(label, actorId, clientId, note, holdSeconds = 0) {
  const hold = holdSeconds > 0
    ? `select pg_catalog.pg_sleep(${Number(holdSeconds)});`
    : '';
  return `
    begin;
    set local lock_timeout = '10s';
    set local statement_timeout = '20s';
    select pg_catalog.set_config(
      'request.jwt.claims', '{"role":"authenticated"}', true
    );
    select pg_catalog.set_config(
      'request.jwt.claim.sub', ${sqlLiteral(actorId)}, true
    );
    select pg_catalog.set_config('crm.producto_condicion_id', '', true);
    with resultado as (
      select public.crear_contrato(
        pg_catalog.jsonb_build_object(
          'cliente_id', ${sqlLiteral(clientId)},
          'capital', 500,
          'moneda', 'PEN',
          'tasa_anual', 15,
          'modalidad', 'mensual',
          'tipo_interes', 'simple',
          'fecha_inicio', (pg_catalog.now() at time zone 'America/Lima')::date,
          'fecha_vencimiento', (pg_catalog.now() at time zone 'America/Lima')::date + 365,
          'categoria', 'nuevo',
          'notas_internas', ${sqlLiteral(note)}
        ),
        pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
          'numero_cuota', 1,
          'fecha_programada', (pg_catalog.now() at time zone 'America/Lima')::date + 30,
          'monto_programado', 100,
          'tipo', 'cuota'
        ))
      ) as data
    )
    select ${sqlLiteral(`${label}|`)}
      || (data->>'id') || '|'
      || (data->>'numero_contrato')
    from resultado;
    ${hold}
    commit;
  `;
}

async function captureBackendIdentity(session, context) {
  const deadline = performance.now() + 8000;
  while (performance.now() < deadline) {
    if (session.hasExited()) {
      await session.completion;
      throw new Error('la sesión terminó antes de capturar su PID PostgreSQL');
    }

    const rows = await runPsql('capturar PID de backend', `
      select pg_catalog.concat_ws(
        '|', a.pid, a.datname, a.usename, a.application_name, a.backend_type
      )
      from pg_catalog.pg_stat_activity a
      where a.application_name = ${sqlLiteral(session.applicationName)}
      order by a.pid;
    `);
    if (!rows) {
      await sleep(50);
      continue;
    }

    const matches = rows.split('\n');
    if (matches.length !== 1) {
      throw new Error(
        `application_name no identifica un único backend (${matches.length} filas)`,
      );
    }
    const [pidText, datname, usename, applicationName, backendType, ...extra] =
      matches[0].split('|');
    if (!/^\d+$/.test(pidText)
        || datname !== context.databaseName
        || usename !== context.serverUser
        || applicationName !== session.applicationName
        || backendType !== 'client backend'
        || extra.length > 0) {
      throw new Error(`identidad de backend inesperada: ${matches[0]}`);
    }
    session.backendPid = Number(pidText);
    return;
  }
  throw new Error('no se capturó el PID PostgreSQL de la sesión dentro de 8 s');
}

async function waitForNumberingLock(year, firstSession, context) {
  const deadline = performance.now() + 8000;
  while (performance.now() < deadline) {
    if (firstSession.hasExited()) {
      await firstSession.completion;
      throw new Error('la sesión 1 terminó antes de mantener abierto el mutex anual');
    }

    const count = await runPsql('detectar mutex anual', `
      with key as (
        select case
          when pg_catalog.hashtext('public.contratos.numero_contrato') < 0
            then pg_catalog.hashtext('public.contratos.numero_contrato')::bigint + 4294967296
          else pg_catalog.hashtext('public.contratos.numero_contrato')::bigint
        end as classid
      )
      select count(*)
      from pg_catalog.pg_locks l
      join pg_catalog.pg_stat_activity a on a.pid = l.pid
      cross join key k
      where l.locktype = 'advisory'
        and l.granted
        and l.objsubid = 2
        and l.classid::bigint = k.classid
        and l.objid::bigint = ${Number(year)}
        and a.pid = ${firstSession.backendPid}
        and a.application_name = ${sqlLiteral(firstSession.applicationName)}
        and a.datname = ${sqlLiteral(context.databaseName)}
        and a.usename = ${sqlLiteral(context.serverUser)}
        and a.backend_type = 'client backend';
    `);
    if (Number(count) > 0) return;
    await sleep(100);
  }
  throw new Error('no se observó el mutex anual de la sesión 1 dentro de 8 s');
}

async function waitForNumberingLockWaiter(year, secondSession, context) {
  const deadline = performance.now() + 8000;
  while (performance.now() < deadline) {
    if (secondSession.hasExited()) {
      await secondSession.completion;
      throw new Error('la sesión 2 terminó antes de esperar el mutex anual');
    }

    const count = await runPsql('detectar espera de mutex anual', `
      with key as (
        select case
          when pg_catalog.hashtext('public.contratos.numero_contrato') < 0
            then pg_catalog.hashtext('public.contratos.numero_contrato')::bigint + 4294967296
          else pg_catalog.hashtext('public.contratos.numero_contrato')::bigint
        end as classid
      )
      select count(*)
      from pg_catalog.pg_locks l
      join pg_catalog.pg_stat_activity a on a.pid = l.pid
      cross join key k
      where l.locktype = 'advisory'
        and not l.granted
        and l.objsubid = 2
        and l.classid::bigint = k.classid
        and l.objid::bigint = ${Number(year)}
        and a.pid = ${secondSession.backendPid}
        and a.application_name = ${sqlLiteral(secondSession.applicationName)}
        and a.datname = ${sqlLiteral(context.databaseName)}
        and a.usename = ${sqlLiteral(context.serverUser)}
        and a.backend_type = 'client backend';
    `);
    if (Number(count) > 0) return;
    await sleep(100);
  }
  throw new Error('no se observó a la sesión 2 esperando el mutex anual dentro de 8 s');
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

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function parseUuid(value, label) {
  if (!uuidPattern.test(value)) {
    throw new Error(`${label}: el servidor devolvió un identificador no UUID`);
  }
  return value;
}

function parseUuidCsv(value, label) {
  if (!value) return [];
  const ids = value.split(',').filter(Boolean);
  if (ids.some((id) => !uuidPattern.test(id))) {
    throw new Error(`${label}: el servidor devolvió identificadores no UUID`);
  }
  return [...new Set(ids)];
}

function parseContractOutput(session, label, note, required = false) {
  const lines = session.stdout().split('\n').filter((line) => line.startsWith(`${label}|`));
  if (lines.length === 0 && !required) return null;
  if (lines.length !== 1) {
    throw new Error(`${label}: se esperó una salida de contrato y llegaron ${lines.length}`);
  }
  const match = lines[0].match(
    /^S[12]\|([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\|(AC-\d{4}-\d{4})$/i,
  );
  if (!match || !lines[0].startsWith(`${label}|`)) {
    throw new Error(`${label}: salida de contrato no reconocida: ${lines[0]}`);
  }
  return { id: parseUuid(match[1], `${label}.id`), label, note, number: match[2] };
}

function uuidArraySql(ids) {
  if (ids.length === 0) return 'array[]::uuid[]';
  return `array[${ids.map((id) => `${sqlLiteral(id)}::uuid`).join(', ')}]`;
}

function textArraySql(ids) {
  if (ids.length === 0) return 'array[]::text[]';
  return `array[${ids.map(sqlLiteral).join(', ')}]::text[]`;
}

function expectedTargetsSql(targets) {
  if (targets.length === 0) {
    return 'select null::uuid as id, null::text as note where false';
  }
  return `values ${targets.map((target) => (
    `(${sqlLiteral(target.id)}::uuid, ${sqlLiteral(target.note)}::text)`
  )).join(', ')}`;
}

async function loadContext() {
  const preflight = await runPsql('preflight local', `
    select pg_catalog.concat_ws(
      '|',
      pg_catalog.current_database(),
      coalesce(pg_catalog.inet_server_addr()::text, ''),
      current_user,
      r.rolsuper::text,
      gerencia.id::text,
      cliente.id::text,
      extract(year from pg_catalog.now() at time zone 'America/Lima')::integer::text,
      (to_regprocedure('private.siguiente_numero_contrato(integer)') is not null)::text,
      pg_catalog.md5(pg_catalog.to_jsonb(cliente)::text)
    )
    from pg_catalog.pg_roles r
    cross join public.perfiles gerencia
    join crm.equipo equipo on equipo.perfil_id = gerencia.id
    cross join public.perfiles cliente
    where r.rolname = current_user
      and gerencia.correo = 'gerencia.crm@demo.avancecorp.pe'
      and gerencia.activo is true
      and equipo.activo is true
      and equipo.rol_crm = 'gerencia'
      and cliente.correo = 'cliente-bancario.crm@demo.avancecorp.pe'
      and cliente.activo is true
    limit 1;
  `);
  const [
    serverDb, serverAddress, serverUser, isSuperuser, actorId, clientId,
    yearText, helperExists, clientFingerprint, ...extra
  ] = preflight.split('|');

  if (serverDb !== databaseName) {
    throw new Error(`la URL apunta a ${databaseName}, pero el servidor reportó ${serverDb}`);
  }
  const serverHost = serverAddress.split('/')[0];
  const localContainerAddress = /^(?:10\.|192\.168\.|172\.(?:1[6-9]|2\d|3[01])\.)/.test(serverHost);
  if (!['127.0.0.1', '::1'].includes(serverHost) && !localContainerAddress) {
    throw new Error(`inet_server_addr no es loopback/bridge local: ${serverAddress || '(socket/indeterminado)'}`);
  }
  // Supabase local entrega una cuenta `postgres` administrada con rolsuper=f,
  // pero con los privilegios de dueño necesarios para fixtures y cleanup.
  if (serverUser !== databaseUser
      || serverUser !== 'postgres'
      || !['true', 'false'].includes(isSuperuser)) {
    throw new Error(`cuenta local no reconocida para cleanup: ${serverUser}`);
  }
  if (!actorId || !clientId || helperExists !== 'true'
      || !/^[0-9a-f]{32}$/i.test(clientFingerprint)
      || extra.length > 0) {
    throw new Error(`preflight incompleto: ${preflight || '(sin filas)'}`);
  }
  parseUuid(actorId, 'actor de preflight');
  parseUuid(clientId, 'cliente de preflight');

  const year = Number(yearText);
  if (!Number.isInteger(year)) {
    throw new Error(`año de preflight inválido: ${yearText}`);
  }
  return {
    actorId,
    clientFingerprint,
    clientId,
    databaseName: serverDb,
    serverUser,
    year,
  };
}

async function assertSharedClientUnchanged(context) {
  const fingerprint = await runPsql('verificar cliente compartido intacto', `
    select pg_catalog.md5(pg_catalog.to_jsonb(p)::text)
    from public.perfiles p
    where p.id = ${sqlLiteral(context.clientId)}::uuid;
  `);
  if (fingerprint !== context.clientFingerprint) {
    throw new Error(
      'la fila del cliente compartido cambió; el runner no la restauró ni la sobrescribió',
    );
  }
}

async function assertScenarioNamespaceUnused(notes) {
  const notesSql = textArraySql(notes);
  const state = await runPsql('verificar namespace único de corrida', `
    select pg_catalog.concat_ws(
      '|',
      (select count(*) from public.contratos c
       where c.notas_internas = any(${notesSql})),
      (select count(*) from public.audit_log a
       where coalesce(
         a.data_despues->>'notas_internas',
         a.data_antes->>'notas_internas'
       ) = any(${notesSql}))
    );
  `);
  if (state !== '0|0') {
    throw new Error(`colisión en notas UUID antes de iniciar (contratos|auditoría=${state})`);
  }
}

async function terminateTrackedSessions(sessions, context) {
  const tracked = sessions.filter((session) => Number.isInteger(session.backendPid));
  if (tracked.length === 0) return 0;
  const targetsSql = tracked.map((session) => (
    `(${session.backendPid}::integer, ${sqlLiteral(session.applicationName)}::text)`
  )).join(', ');
  const observedPids = new Set();
  const terminatedPids = new Set();
  const deadline = performance.now() + 8000;

  while (performance.now() < deadline) {
    const results = await runPsql('terminar sesiones concurrentes', `
      with target(pid, application_name) as (values ${targetsSql})
      select a.pid::text || '|' ||
        pg_catalog.pg_terminate_backend(a.pid)::text
      from pg_catalog.pg_stat_activity a
      join target t
        on t.pid = a.pid
       and t.application_name = a.application_name
      where a.datname = ${sqlLiteral(context.databaseName)}
        and a.usename = ${sqlLiteral(context.serverUser)}
        and a.backend_type = 'client backend'
        and a.pid <> pg_catalog.pg_backend_pid()
      order by a.pid;
    `);
    if (!results) return terminatedPids.size;
    for (const row of results.split('\n')) {
      const [pid, terminated, ...extra] = row.split('|');
      if (!/^\d+$/.test(pid) || !['true', 'false'].includes(terminated) || extra.length > 0) {
        throw new Error(`respuesta de pg_terminate_backend no reconocida: ${row}`);
      }
      observedPids.add(pid);
      if (terminated === 'true') terminatedPids.add(pid);
    }
    await sleep(100);
  }
  throw new Error(`siguen activos backends rastreados tras 8 s (${[...observedPids].join(', ')})`);
}

async function assertTrackedSessionsGone(sessions, context) {
  if (sessions.length === 0) return;
  const applicationNames = textArraySql(sessions.map((session) => session.applicationName));
  const remaining = await runPsql('verificar cierre exacto de sesiones', `
    select count(*)
    from pg_catalog.pg_stat_activity a
    where a.application_name = any(${applicationNames})
      and a.datname = ${sqlLiteral(context.databaseName)}
      and a.usename = ${sqlLiteral(context.serverUser)}
      and a.backend_type = 'client backend';
  `);
  if (remaining !== '0') {
    throw new Error(`quedaron ${remaining} backends de la corrida`);
  }
}

async function cleanupScenario(notes, capturedTargets) {
  const byId = new Map();
  for (const target of capturedTargets) {
    const previous = byId.get(target.id);
    if (previous && previous.note !== target.note) {
      throw new Error(`un UUID de contrato apareció con dos notas: ${target.id}`);
    }
    byId.set(target.id, target);
  }
  const targets = [...byId.values()];
  const expectedSql = expectedTargetsSql(targets);
  const notesSql = textArraySql(notes);

  // Las notas solo prueban unicidad. Nunca amplían el conjunto a borrar: una
  // fila/auditoría con nota propia pero UUID no capturado aborta antes del DELETE.
  const namespaceState = await runPsql('validar objetivos exactos de cleanup', `
    with expected(id, note) as (${expectedSql})
    select pg_catalog.concat_ws(
      '|',
      (select count(*)
       from public.contratos c
       where c.notas_internas = any(${notesSql})
         and not exists (
           select 1 from expected e where e.id = c.id and e.note = c.notas_internas
         )),
      (select count(*)
       from public.contratos c
       join expected e on e.id = c.id
       where c.notas_internas is distinct from e.note),
      (select count(*)
       from public.audit_log a
       where coalesce(
         a.data_despues->>'notas_internas',
         a.data_antes->>'notas_internas'
       ) = any(${notesSql})
         and not exists (
           select 1
           from expected e
           where e.id::text = coalesce(
             a.data_despues->>'id', a.data_antes->>'id', a.fila_id
           )
             and e.note = coalesce(
               a.data_despues->>'notas_internas',
               a.data_antes->>'notas_internas'
             )
         ))
    );
  `);
  if (namespaceState !== '0|0|0') {
    throw new Error(
      `cleanup abortado por objetivo desconocido (contrato-nota|id-nota|auditoría=${namespaceState})`,
    );
  }

  const contractIds = targets.map((target) => target.id);
  const contractArray = uuidArraySql(contractIds);
  const dependencies = await runPsql('capturar dependencias por UUID de contrato', `
    select pg_catalog.concat_ws(
      '|',
      coalesce((select pg_catalog.string_agg(pc.id::text, ',' order by pc.id)
        from crm.producto_condiciones pc
        where pc.es_legacy
          and pc.legacy_contrato_id = any(${contractArray})), ''),
      coalesce((select pg_catalog.string_agg(distinct pc.version_id::text, ',' order by pc.version_id::text)
        from crm.producto_condiciones pc
        where pc.es_legacy
          and pc.legacy_contrato_id = any(${contractArray})), '')
    );
  `);
  const [conditionCsv = '', versionCsv = '', ...dependencyExtra] = dependencies.split('|');
  if (dependencyExtra.length > 0) {
    throw new Error(`respuesta de dependencias no reconocida: ${dependencies}`);
  }
  const conditionIds = parseUuidCsv(conditionCsv, 'condiciones de cleanup');
  const versionIds = parseUuidCsv(versionCsv, 'versiones de cleanup');
  const conditionArray = uuidArraySql(conditionIds);
  const versionArray = uuidArraySql(versionIds);
  const contractTextIds = textArraySql(contractIds);
  const conditionTextIds = textArraySql(conditionIds);
  const versionTextIds = textArraySql(versionIds);

  await runPsql('cleanup local', `
    begin;
    set local session_replication_role = replica;
    delete from public.cronograma_pagos q
    where q.contrato_id = any(${contractArray});
    delete from public.contratos c
    using (${expectedSql}) as expected(id, note)
    where c.id = expected.id
      and c.notas_internas = expected.note;
    delete from crm.producto_condiciones pc
    where pc.id = any(${conditionArray})
      and pc.es_legacy
      and pc.legacy_contrato_id = any(${contractArray})
      and not exists (
        select 1 from public.contratos c where c.producto_condicion_id = pc.id
      );
    delete from crm.producto_versiones pv
    where pv.id = any(${versionArray})
      and not exists (
        select 1 from crm.producto_condiciones pc where pc.version_id = pv.id
      );
    delete from public.audit_log a
    where (a.tabla = 'contratos' and (
         a.fila_id = any(${contractTextIds})
         or coalesce(a.data_despues->>'id', a.data_antes->>'id') = any(${contractTextIds})
       ))
       or (a.tabla = 'crm.producto_condiciones' and (
         a.fila_id = any(${conditionTextIds})
         or coalesce(a.data_despues->>'id', a.data_antes->>'id') = any(${conditionTextIds})
       ))
       or (a.tabla = 'crm.producto_versiones' and (
         a.fila_id = any(${versionTextIds})
         or coalesce(a.data_despues->>'id', a.data_antes->>'id') = any(${versionTextIds})
       ))
       or (a.tabla = 'cronograma_pagos' and coalesce(
         a.data_despues->>'contrato_id', a.data_antes->>'contrato_id'
       ) = any(${contractTextIds}));
    set local session_replication_role = origin;
    commit;
  `);

  const remaining = await runPsql('verificar cleanup local', `
    select pg_catalog.concat_ws(
      '|',
      (select count(*) from public.contratos c
       where c.id = any(${contractArray})
          or c.notas_internas = any(${notesSql})),
      (select count(*) from public.cronograma_pagos q
       where q.contrato_id = any(${contractArray})),
      (select count(*) from crm.producto_condiciones pc
       where pc.id = any(${conditionArray})),
      (select count(*) from crm.producto_versiones pv
       where pv.id = any(${versionArray})),
      (select count(*) from public.audit_log a
       where (a.tabla = 'contratos' and (
            a.fila_id = any(${contractTextIds})
            or coalesce(a.data_despues->>'id', a.data_antes->>'id') = any(${contractTextIds})
          ))
          or (a.tabla = 'crm.producto_condiciones' and (
            a.fila_id = any(${conditionTextIds})
            or coalesce(a.data_despues->>'id', a.data_antes->>'id') = any(${conditionTextIds})
          ))
          or (a.tabla = 'crm.producto_versiones' and (
            a.fila_id = any(${versionTextIds})
            or coalesce(a.data_despues->>'id', a.data_antes->>'id') = any(${versionTextIds})
          ))
          or (a.tabla = 'cronograma_pagos' and coalesce(
            a.data_despues->>'contrato_id', a.data_antes->>'contrato_id'
          ) = any(${contractTextIds}))
          or coalesce(
            a.data_despues->>'notas_internas',
            a.data_antes->>'notas_internas'
          ) = any(${notesSql}))
    );
  `);
  if (remaining !== '0|0|0|0|0') {
    throw new Error(`quedaron residuos contrato|cronograma|condición|versión|auditoría: ${remaining}`);
  }
  return { contractIds };
}

async function runScenario(context, { injectFailure }) {
  const runId = randomUUID();
  const note1 = `GCAR CONCURRENCIA LOCAL ${runId} S1`;
  const note2 = `GCAR CONCURRENCIA LOCAL ${runId} S2`;
  const notes = [note1, note2];
  const applicationPrefix = `gcar_contrato_${runId.replaceAll('-', '')}`;
  let primaryError;
  let expectedFailureObserved = false;
  let session1;
  let session2;
  let result;
  let terminatedBackends = 0;

  try {
    await assertScenarioNamespaceUnused(notes);
    session1 = startPsql(
      'sesión 1',
      createContractSql('S1', context.actorId, context.clientId, note1, 4),
      `${applicationPrefix}_s1`,
    );
    session1.resultLabel = 'S1';
    session1.note = note1;

    await captureBackendIdentity(session1, context);
    await waitForNumberingLock(context.year, session1, context);
    if (injectFailure) {
      expectedFailureObserved = true;
      throw new Error('fallo inyectado después de observar el mutex de la sesión 1');
    }

    const secondStartedAt = performance.now();
    let secondFinishedAt;
    session2 = startPsql(
      'sesión 2',
      createContractSql('S2', context.actorId, context.clientId, note2),
      `${applicationPrefix}_s2`,
    );
    session2.resultLabel = 'S2';
    session2.note = note2;
    const timedSecondCompletion = session2.completion.then((output) => {
      secondFinishedAt = performance.now();
      return output;
    });
    void timedSecondCompletion.catch(() => {});
    await captureBackendIdentity(session2, context);
    await waitForNumberingLockWaiter(context.year, session2, context);
    const [session1Output, session2Output] = await Promise.all([
      session1.completion,
      timedSecondCompletion,
    ]);
    const secondElapsedMs = Math.round(secondFinishedAt - secondStartedAt);

    const contract1 = parseContractOutput(session1, 'S1', note1, true);
    const contract2 = parseContractOutput(session2, 'S2', note2, true);
    const { number: number1 } = contract1;
    const { number: number2 } = contract2;
    if (!number1.startsWith(`AC-${context.year}-`) || !number2.startsWith(`AC-${context.year}-`)) {
      throw new Error(`año no Lima: esperado ${context.year}; recibido ${number1}, ${number2}`);
    }

    const sequence1 = Number(number1.slice(-4));
    const sequence2 = Number(number2.slice(-4));
    if (number1 === number2 || sequence2 !== sequence1 + 1) {
      throw new Error(`correlativos no consecutivos: ${number1}, ${number2}`);
    }
    const persisted = await runPsql('verificar commits', `
      with expected(id, note) as (values
        (${sqlLiteral(contract1.id)}::uuid, ${sqlLiteral(note1)}::text),
        (${sqlLiteral(contract2.id)}::uuid, ${sqlLiteral(note2)}::text)
      )
      select count(*)::text || '|' || pg_catalog.string_agg(
        c.numero_contrato, ',' order by c.numero_contrato
      )
      from public.contratos c
      join expected e on e.id = c.id and e.note = c.notas_internas;
    `);
    if (persisted !== `2|${number1},${number2}`) {
      throw new Error(
        `persistencia inesperada por UUID exacto: ${persisted}; `
        + `S1=${session1Output}; S2=${session2Output}`,
      );
    }
    result = {
      contractIds: [contract1.id, contract2.id],
      number1,
      number2,
      secondElapsedMs,
    };
  } catch (error) {
    const current = asError(error);
    const isExpected = injectFailure
      && expectedFailureObserved
      && current.message === 'fallo inyectado después de observar el mutex de la sesión 1';
    if (!isExpected) primaryError = current;
  } finally {
    const sessions = [session1, session2].filter(Boolean);
    try {
      terminatedBackends += await terminateTrackedSessions(sessions, context);
    } catch (error) {
      primaryError = appendError(primaryError, 'Cierre de sesiones falló', error);
    }

    for (const session of sessions) {
      if (!session.hasExited()) session.child.kill('SIGTERM');
    }
    await Promise.allSettled(sessions.map((session) => session.completion));

    const capturedTargets = [];
    for (const session of sessions) {
      try {
        const target = parseContractOutput(
          session,
          session.resultLabel,
          session.note,
          false,
        );
        if (target) capturedTargets.push(target);
      } catch (error) {
        primaryError = appendError(primaryError, 'Captura de UUID para cleanup falló', error);
      }
    }

    try {
      terminatedBackends += await terminateTrackedSessions(sessions, context);
      await assertTrackedSessionsGone(sessions, context);
    } catch (error) {
      primaryError = appendError(primaryError, 'Postcondición de sesiones falló', error);
    }

    try {
      await cleanupScenario(notes, capturedTargets);
    } catch (error) {
      primaryError = appendError(primaryError, 'Cleanup falló', error);
    }

    try {
      await assertSharedClientUnchanged(context);
    } catch (error) {
      primaryError = appendError(primaryError, 'Aislamiento del cliente falló', error);
    }
  }

  if (injectFailure && !expectedFailureObserved) {
    primaryError = appendError(primaryError, 'Fallo inyectado no observado', 'la sesión 1 no alcanzó el mutex');
  }
  if (injectFailure && terminatedBackends < 1) {
    primaryError = appendError(
      primaryError,
      'Fallo inyectado no ejercitó la terminación',
      'pg_terminate_backend no devolvió true para ningún backend rastreado',
    );
  }
  if (primaryError) throw primaryError;
  return result;
}

try {
  const context = await loadContext();
  await runScenario(context, { injectFailure: true });
  console.log('CREAR_CONTRATO_CONCURRENCIA_FALLO_INYECTADO_CLEANUP_OK');

  const result = await runScenario(context, { injectFailure: false });
  console.log('CREAR_CONTRATO_CONCURRENCIA_LOCAL_OK');
  console.log(
    `Numeración: ${result.number1} → ${result.number2}; `
    + `espera sesión 2: ${result.secondElapsedMs} ms.`,
  );
  console.log(
    `Aislamiento: cleanup exacto por ${result.contractIds.length} UUID; `
    + 'cliente compartido intacto.',
  );
} catch (error) {
  console.error(asError(error).message);
  process.exitCode = 1;
}
