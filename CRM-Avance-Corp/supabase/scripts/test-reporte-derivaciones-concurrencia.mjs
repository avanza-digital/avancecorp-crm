#!/usr/bin/env node

// Gate hermetico de dos sesiones para el orden causal entre derivar y gestionar.
// Cada escenario crea su propio lead y tarea, confirma cambios entre backends y
// elimina solo las filas ligadas a esos UUID. La base debe ser local y desechable.

import { randomUUID } from 'node:crypto';
import { spawn } from 'node:child_process';
import { performance } from 'node:perf_hooks';
import process from 'node:process';

const databaseUrl = process.env.TEST_DATABASE_URL;
const psqlBin = process.env.PSQL_BIN || 'psql';
const disposableAck = process.env.GCAR_LOCAL_DISPOSABLE;
const PID_PREFIX = 'GCAR_BACKEND_PID|';
const SAFE_PGOPTIONS = '-c statement_timeout=20000 -c lock_timeout=10000';

const TRACKED_TABLES = [
  ['public.audit_log', 'public.audit_log'],
  ['crm.actividades', 'crm.actividades'],
  ['crm.actividades_cliente', 'crm.actividades_cliente'],
  ['crm.ajustes_mes_cerrado', 'crm.ajustes_mes_cerrado'],
  ['crm.cierres_avance_anulados', 'crm.cierres_avance_anulados'],
  ['crm.cierres_externos', 'crm.cierres_externos'],
  ['crm.conversion_reservas', 'crm.conversion_reservas'],
  ['crm.lead_asignacion_sla_hitos', 'crm.lead_asignacion_sla_hitos'],
  ['crm.lead_asignaciones', 'crm.lead_asignaciones'],
  ['crm.lead_sla_ciclos', 'crm.lead_sla_ciclos'],
  ['crm.lead_sla_etapas', 'crm.lead_sla_etapas'],
  ['crm.leads', 'crm.leads'],
  ['crm.tareas', 'crm.tareas'],
];

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
// No se admite ni siquiera un parametro inocuo: libpq reconoce opciones como
// hostaddr y options que podrian contradecir el host o application_name validados.
if (databaseUrl.includes('?') || databaseUrl.includes('#')) {
  failSafety('TEST_DATABASE_URL no puede contener query ni hash.');
}

let parsedUrl;
try {
  parsedUrl = new URL(databaseUrl);
} catch {
  failSafety('TEST_DATABASE_URL no es una URL PostgreSQL valida.');
}

if (!['postgres:', 'postgresql:'].includes(parsedUrl.protocol)) {
  failSafety('TEST_DATABASE_URL debe usar postgres:// o postgresql://.');
}

let databaseName;
let databaseUser;
let databasePassword;
try {
  databaseName = decodeURIComponent(parsedUrl.pathname.replace(/^\//, ''));
  databaseUser = decodeURIComponent(parsedUrl.username);
  databasePassword = decodeURIComponent(parsedUrl.password);
} catch {
  failSafety('TEST_DATABASE_URL contiene escapes percentuales invalidos.');
}

const databaseHost = parsedUrl.hostname.replace(/^\[(.*)\]$/, '$1');
if (!['127.0.0.1', 'localhost', '::1'].includes(databaseHost)) {
  failSafety(`host no local rechazado: ${databaseHost || '(vacio)'}.`);
}
if (databaseUser !== 'postgres') {
  failSafety(`usuario local no permitido: ${databaseUser || '(vacio)'}.`);
}
if (!databasePassword) {
  failSafety('TEST_DATABASE_URL debe incluir password para pasarlo solo por PGPASSWORD.');
}

const databasePort = parsedUrl.port || '5432';
if (!/^\d{1,5}$/.test(databasePort)
    || Number(databasePort) < 1
    || Number(databasePort) > 65535) {
  failSafety(`puerto PostgreSQL invalido: ${databasePort || '(vacio)'}.`);
}

// Anclado de extremo a extremo: solo gcar_* o gcar-* y, ademas, una marca
// explicita de desechabilidad dentro del nombre.
const disposableDatabaseShape = /^gcar(?:[_-][a-z0-9]+)+$/i;
const databaseTokens = databaseName.toLowerCase().split(/[_-]/).slice(1);
const disposableTokens = new Set(['fix', 'test', 'tmp', 'local']);
const forbiddenDatabaseTokens = new Set(['canonical', 'live', 'main', 'prod', 'production']);
if (!databaseName
    || !disposableDatabaseShape.test(databaseName)
    || !databaseTokens.some((token) => disposableTokens.has(token))
    || databaseTokens.some((token) => forbiddenDatabaseTokens.has(token))) {
  failSafety(`nombre de DB no reconocible como desechable: ${databaseName || '(vacio)'}.`);
}

const connectionArgs = [
  '-h', databaseHost,
  '-p', databasePort,
  '-U', databaseUser,
  '-d', databaseName,
];

function sqlLiteral(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function jsonbSql(value) {
  return `${sqlLiteral(JSON.stringify(value))}::jsonb`;
}

function globalCountsSql() {
  return `pg_catalog.jsonb_build_object(
    ${TRACKED_TABLES.map(
    ([key, table]) => `${sqlLiteral(key)}, (select count(*) from ${table})`,
  ).join(',\n    ')}
  )`;
}

let controlSessionCounter = 0;

function nextControlApplicationName() {
  controlSessionCounter += 1;
  return `gcar_deriv_ctl_${process.pid}_${controlSessionCounter}`;
}

function childEnvironment(applicationName) {
  const environment = { ...process.env };
  // Los argumentos -h/-p/-U/-d son la unica fuente de destino. Se eliminan
  // variables libpq capaces de redirigir la conexion o de cargar credenciales.
  for (const variable of Object.keys(environment)) {
    if (/^PG[A-Z0-9_]*$/.test(variable) || variable === 'TEST_DATABASE_URL') {
      delete environment[variable];
    }
  }

  // PGOPTIONS se reconstruye en vez de heredarse: ningun valor externo puede
  // sobrescribir application_name ni debilitar los timeouts del gate.
  environment.PGOPTIONS = SAFE_PGOPTIONS;
  environment.PGAPPNAME = applicationName;
  environment.PGCONNECT_TIMEOUT = '5';
  environment.PGPASSWORD = databasePassword;
  environment.PGSSLMODE = 'disable';
  return environment;
}

function startPsql(label, sql, applicationName = nextControlApplicationName()) {
  if (!/^[a-z0-9_]{1,63}$/.test(applicationName)) {
    throw new Error(`${label}: application_name interno invalido`);
  }

  const pidSql = `select ${sqlLiteral(PID_PREFIX)} || pg_catalog.pg_backend_pid()::text;`;
  const child = spawn(
    psqlBin,
    [
      '-X',
      '--no-password',
      '-v', 'ON_ERROR_STOP=1',
      '-qAt',
      ...connectionArgs,
      // Dos -c fuerzan dos intercambios de protocolo en el mismo backend. Asi
      // psql entrega el PID antes de entrar en la sentencia que puede bloquear.
      '-c', pidSql,
      '-c', sql,
    ],
    {
      stdio: ['ignore', 'pipe', 'pipe'],
      env: childEnvironment(applicationName),
    },
  );

  let stdout = '';
  let stderr = '';
  let exited = false;
  let capturedPid;
  let pidCaptureError;
  let resolveBackendPid;
  let rejectBackendPid;
  const backendPid = new Promise((resolve, reject) => {
    resolveBackendPid = resolve;
    rejectBackendPid = reject;
  });
  void backendPid.catch(() => {});

  function capturePidFromFirstLine({ final = false } = {}) {
    if (capturedPid !== undefined || pidCaptureError) return;
    const lineBreak = stdout.indexOf('\n');
    if (lineBreak < 0 && !final) return;
    const firstLine = (lineBreak < 0 ? stdout : stdout.slice(0, lineBreak)).replace(/\r$/, '');
    const match = /^GCAR_BACKEND_PID\|(\d+)$/.exec(firstLine);
    if (!match) {
      pidCaptureError = new Error(
        `${label}: no se pudo capturar el PID real del backend: ${firstLine || '(sin salida)'}`,
      );
      rejectBackendPid(pidCaptureError);
      return;
    }
    capturedPid = Number(match[1]);
    resolveBackendPid(capturedPid);
  }

  child.stdout.on('data', (chunk) => {
    stdout += chunk;
    capturePidFromFirstLine();
  });
  child.stderr.on('data', (chunk) => { stderr += chunk; });

  const completion = new Promise((resolve, reject) => {
    child.on('error', (error) => {
      exited = true;
      if (capturedPid === undefined && !pidCaptureError) {
        pidCaptureError = new Error(`${label}: ${error.message}`);
        rejectBackendPid(pidCaptureError);
      }
      reject(new Error(`${label}: ${error.message}`));
    });
    child.on('close', (code) => {
      exited = true;
      capturePidFromFirstLine({ final: true });
      if (code !== 0) {
        reject(new Error(`${label}: psql termino ${code}\n${stderr || stdout}`));
        return;
      }
      if (pidCaptureError || capturedPid === undefined) {
        reject(pidCaptureError || new Error(`${label}: PID de backend ausente`));
        return;
      }
      const firstLineBreak = stdout.indexOf('\n');
      resolve(firstLineBreak < 0 ? '' : stdout.slice(firstLineBreak + 1).trim());
    });
  });
  // El finally espera todas las sesiones; este manejador evita un rechazo no
  // atendido si otra operacion falla antes de alcanzar ese punto.
  void completion.catch(() => {});

  return {
    applicationName,
    backendPid,
    child,
    completion,
    hasExited: () => exited,
  };
}

async function runPsql(label, sql) {
  return startPsql(label, sql).completion;
}

const sleep = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));

function asError(error) {
  return error instanceof Error ? error : new Error(String(error));
}

function appendError(primary, label, error) {
  const next = asError(error);
  return primary
    ? new Error(`${primary.message}\n${label}: ${next.message}`)
    : new Error(`${label}: ${next.message}`);
}

async function backendPidWithin(session, milliseconds = 3000) {
  let timeout;
  try {
    return await Promise.race([
      session.backendPid,
      new Promise((resolve, reject) => {
        timeout = setTimeout(
          () => reject(new Error('timeout al capturar PID real del backend')),
          milliseconds,
        );
      }),
    ]);
  } finally {
    clearTimeout(timeout);
  }
}

async function waitForPgSleep(session) {
  const backendPid = await backendPidWithin(session);
  const deadline = performance.now() + 8000;
  while (performance.now() < deadline) {
    if (session.hasExited()) {
      await session.completion;
      throw new Error('la sesion 1 termino antes de entrar en pg_sleep');
    }

    const count = await runPsql('observar pg_sleep de la sesion 1', `
      select count(*)
      from pg_catalog.pg_stat_activity activity
      where activity.pid = ${backendPid}
        and activity.application_name = ${sqlLiteral(session.applicationName)}
        and activity.datname = pg_catalog.current_database()
        and activity.usename = current_user
        and activity.backend_type = 'client backend'
        and activity.state = 'active'
        and activity.wait_event_type = 'Timeout'
        and activity.wait_event = 'PgSleep';
    `);
    if (count === '1') return;
    if (count !== '0') {
      throw new Error(`conteo inesperado al observar pg_sleep: ${count || '(vacio)'}`);
    }
    await sleep(100);
  }
  throw new Error('no se observo el pg_sleep de la sesion 1 dentro de 8 s');
}

async function trackedSessionTargets(sessions) {
  const resolved = await Promise.all(sessions.map(async (session) => {
    try {
      return {
        applicationName: session.applicationName,
        pid: await backendPidWithin(session),
      };
    } catch {
      return null;
    }
  }));
  const unique = new Map();
  for (const target of resolved.filter(Boolean)) {
    unique.set(`${target.pid}|${target.applicationName}`, target);
  }
  return [...unique.values()];
}

async function terminateTrackedSessions(sessions) {
  if (sessions.length === 0) return 0;
  const targets = await trackedSessionTargets(sessions);
  if (targets.length === 0) return 0;

  const valuesSql = targets.map(
    (target) => `(${target.pid}::integer, ${sqlLiteral(target.applicationName)}::text)`,
  ).join(',\n        ');
  const observedPids = new Set();
  const terminatedPids = new Set();
  const deadline = performance.now() + 8000;
  while (performance.now() < deadline) {
    const results = await runPsql('terminar sesiones concurrentes', `
      with tracked(pid, application_name) as (
        values ${valuesSql}
      )
      select activity.pid::text
        || '|' || pg_catalog.pg_terminate_backend(activity.pid)::text
      from pg_catalog.pg_stat_activity activity
      join tracked
        on tracked.pid = activity.pid
       and tracked.application_name = activity.application_name
      where activity.datname = pg_catalog.current_database()
        and activity.usename = current_user
        and activity.backend_type = 'client backend'
        and activity.pid <> pg_catalog.pg_backend_pid()
      order by activity.pid;
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
  throw new Error(
    `siguen activos backends rastreados tras 8 s (${[...observedPids].join(', ')})`,
  );
}

function parseJsonObject(raw, label) {
  let value;
  try {
    value = JSON.parse(raw);
  } catch {
    throw new Error(`${label} no devolvio JSON valido: ${raw || '(sin filas)'}`);
  }
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error(`${label} no devolvio un objeto JSON`);
  }
  return value;
}

function parsePreflight(raw) {
  const value = parseJsonObject(raw, 'preflight');
  if (value.database !== databaseName) {
    throw new Error(`la URL apunta a ${databaseName}, pero el servidor reporto ${value.database}`);
  }
  const serverHost = String(value.server_address || '').split('/')[0];
  const localContainerAddress = /^(?:10\.|192\.168\.|172\.(?:1[6-9]|2\d|3[01])\.)/.test(serverHost);
  if (!['127.0.0.1', '::1'].includes(serverHost) && !localContainerAddress) {
    throw new Error(
      `inet_server_addr no es loopback/bridge local: ${value.server_address || '(indeterminado)'}`,
    );
  }
  if (value.server_user !== databaseUser || value.server_user !== 'postgres') {
    throw new Error(`cuenta local no reconocida para cleanup: ${value.server_user || '(vacia)'}`);
  }
  if (value.actor_counts !== '1|1' || !value.supervisor_id || !value.analista_id) {
    throw new Error(`actores de sonda ausentes o ambiguos: ${value.actor_counts || '(sin conteos)'}`);
  }
  if (value.functions_ready !== true || value.triggers_ready !== true) {
    throw new Error('faltan las RPC o triggers que sostienen el caso causal');
  }
  if (!value.baseline || typeof value.baseline !== 'object' || Array.isArray(value.baseline)) {
    throw new Error('preflight no capturo los conteos globales');
  }
  const expectedKeys = TRACKED_TABLES.map(([key]) => key).sort();
  const actualKeys = Object.keys(value.baseline).sort();
  if (JSON.stringify(expectedKeys) !== JSON.stringify(actualKeys)
      || Object.values(value.baseline).some(
        (count) => !Number.isSafeInteger(count) || count < 0,
      )) {
    throw new Error('preflight devolvio un baseline global incompleto o invalido');
  }

  return {
    analystId: value.analista_id,
    baseline: value.baseline,
    supervisorId: value.supervisor_id,
  };
}

async function loadPreflight() {
  const raw = await runPsql('preflight local y baseline global', `
    with supervisors as materialized (
      select profile.id
      from public.perfiles profile
      join crm.equipo member on member.perfil_id = profile.id
      where profile.nombre_completo = 'SUPERVISOR UNO'
        and profile.activo = true
        and member.rol_crm = 'supervisor'
        and member.activo = true
    ), analysts as materialized (
      select profile.id
      from public.perfiles profile
      join crm.equipo member on member.perfil_id = profile.id
      join supervisors supervisor on supervisor.id = member.supervisor_id
      where profile.nombre_completo = 'ANALISTA DOS'
        and profile.activo = true
        and member.rol_crm = 'vendedor'
        and member.activo = true
    )
    select pg_catalog.jsonb_build_object(
      'database', pg_catalog.current_database(),
      'server_address', coalesce(pg_catalog.inet_server_addr()::text, ''),
      'server_user', current_user,
      'supervisor_id', (select id from supervisors order by id limit 1),
      'analista_id', (select id from analysts order by id limit 1),
      'actor_counts', pg_catalog.concat_ws(
        '|',
        (select count(*) from supervisors),
        (select count(*) from analysts)
      ),
      'functions_ready',
        pg_catalog.to_regprocedure('crm.derivar_leads_equipo_fn(uuid[],uuid[])') is not null
        and pg_catalog.to_regprocedure('crm.revertir_derivacion_equipo_fn(uuid)') is not null
        and pg_catalog.to_regprocedure('crm.reporte_derivaciones_equipo_fn(date,date)') is not null,
      'triggers_ready', (
        select count(*) = 3
        from pg_catalog.pg_trigger trigger
        where trigger.tgrelid = 'crm.leads'::pg_catalog.regclass
          and trigger.tgname in (
            'trg_leads_reasignacion',
            'trg_leads_asignaciones',
            'trg_leads_zz_sync_tareas'
          )
          and trigger.tgenabled = 'O'
      ),
      'baseline', ${globalCountsSql()}
    )::text;
  `);
  return parsePreflight(raw);
}

function scenarioIdentity() {
  const runId = randomUUID();
  const numericSuffix = (
    BigInt(`0x${runId.replaceAll('-', '')}`) % 1000000000000n
  ).toString().padStart(12, '0');
  return {
    leadId: randomUUID(),
    marker: `SONDA CONCURRENCIA DERIVACIONES ${runId}`,
    probeName: `SONDA DERIVACIONES ${runId}`,
    probePhone: `991${numericSuffix}`,
    runId,
    taskId: randomUUID(),
    taskTitle: `Sonda derivaciones ${runId}`,
  };
}

async function setupScenario(context) {
  return runPsql('crear lead y tarea exclusivos de la sonda', `
    begin;
    set local session_replication_role = replica;

    insert into crm.leads (
      id,
      nombre_completo,
      telefono,
      origen,
      etapa,
      monto_estimado,
      moneda,
      vendedor_id,
      asignado_supervisor_id,
      creado_por
    ) values (
      ${sqlLiteral(context.leadId)}::uuid,
      ${sqlLiteral(context.probeName)},
      ${sqlLiteral(context.probePhone)},
      'otro',
      'nuevo',
      1000.00,
      'PEN',
      null,
      ${sqlLiteral(context.supervisorId)}::uuid,
      ${sqlLiteral(context.supervisorId)}::uuid
    );

    insert into crm.tareas (
      id,
      lead_id,
      vendedor_id,
      asignado_supervisor_id,
      tipo,
      titulo,
      nota,
      vence_en,
      estado,
      activo,
      creado_por
    ) values (
      ${sqlLiteral(context.taskId)}::uuid,
      ${sqlLiteral(context.leadId)}::uuid,
      null,
      ${sqlLiteral(context.supervisorId)}::uuid,
      'tarea',
      ${sqlLiteral(context.taskTitle)},
      ${sqlLiteral(context.marker)},
      pg_catalog.now() + interval '1 day',
      'pendiente',
      true,
      ${sqlLiteral(context.supervisorId)}::uuid
    );

    set local session_replication_role = origin;
    select pg_catalog.concat_ws(
      '|',
      (select count(*) from crm.leads lead
        where lead.id = ${sqlLiteral(context.leadId)}::uuid
          and lead.nombre_completo = ${sqlLiteral(context.probeName)}
          and lead.telefono = ${sqlLiteral(context.probePhone)}
          and lead.vendedor_id is null
          and lead.asignado_supervisor_id = ${sqlLiteral(context.supervisorId)}::uuid),
      (select count(*) from crm.tareas task
        where task.id = ${sqlLiteral(context.taskId)}::uuid
          and task.lead_id = ${sqlLiteral(context.leadId)}::uuid
          and task.titulo = ${sqlLiteral(context.taskTitle)}
          and task.vendedor_id is null
          and task.asignado_supervisor_id = ${sqlLiteral(context.supervisorId)}::uuid)
    );
    commit;
  `);
}

function insertManagementSql(context) {
  return `
    with actor as materialized (
      select pg_catalog.set_config(
        'request.jwt.claim.sub',
        ${sqlLiteral(context.analystId)},
        false
      )
    ), delay as materialized (
      select pg_catalog.pg_sleep(3)
    )
    insert into crm.actividades (
      lead_id, tipo, detalle, metadata, creado_por, creado_en
    )
    select
      ${sqlLiteral(context.leadId)}::uuid,
      'nota',
      ${sqlLiteral(context.marker)},
      pg_catalog.jsonb_build_object(
        'statement_started_at',
        pg_catalog.statement_timestamp()
      ),
      ${sqlLiteral(context.analystId)}::uuid,
      pg_catalog.statement_timestamp()
    from actor
    cross join delay
    returning creado_en;
  `;
}

function deriveSql(context) {
  return `
    with actor as materialized (
      select pg_catalog.set_config(
        'request.jwt.claim.sub',
        ${sqlLiteral(context.supervisorId)},
        false
      )
    )
    select crm.derivar_leads_equipo_fn(
      array[${sqlLiteral(context.leadId)}::uuid],
      array[${sqlLiteral(context.analystId)}::uuid]
    )
    from actor;
  `;
}

async function verifyCausality(context) {
  await runPsql('verificar orden causal y candado de devolucion', `
    do $sonda$
    declare
      v_asignado_en timestamptz;
      v_gestion_en timestamptz;
      v_statement_started_at timestamptz;
      v_reporte jsonb;
      v_reversible boolean;
      v_mensaje text;
    begin
      select assignment.asignado_en
        into v_asignado_en
      from crm.lead_asignaciones assignment
      where assignment.lead_id = ${sqlLiteral(context.leadId)}::uuid
        and assignment.analista_id = ${sqlLiteral(context.analystId)}::uuid
        and assignment.finalizado_en is null;

      select
        activity.creado_en,
        (activity.metadata->>'statement_started_at')::timestamptz
        into v_gestion_en, v_statement_started_at
      from crm.actividades activity
      where activity.lead_id = ${sqlLiteral(context.leadId)}::uuid
        and activity.creado_por = ${sqlLiteral(context.analystId)}::uuid
        and activity.detalle = ${sqlLiteral(context.marker)}
      order by activity.creado_en desc
      limit 1;

      if v_asignado_en is null
         or v_gestion_en is null
         or v_statement_started_at is null then
        raise exception 'C01 falto el episodio o la gestion concurrente';
      end if;
      if not (
        v_statement_started_at < v_asignado_en
        and v_asignado_en <= v_gestion_en
      ) then
        raise exception
          'C02 orden causal invalido: inicio %, asignacion %, gestion %',
          v_statement_started_at, v_asignado_en, v_gestion_en;
      end if;

      perform pg_catalog.set_config(
        'request.jwt.claim.sub',
        ${sqlLiteral(context.supervisorId)},
        true
      );
      v_reporte := crm.reporte_derivaciones_equipo_fn(
        (pg_catalog.now() at time zone 'America/Lima')::date,
        (pg_catalog.now() at time zone 'America/Lima')::date
      );
      select (movement->>'reversible')::boolean
        into v_reversible
      from pg_catalog.jsonb_array_elements(v_reporte->'movimientos_hoy') movement
      where movement->>'lead_id' = ${sqlLiteral(context.leadId)};
      if v_reversible is distinct from false then
        raise exception 'C03 el reporte no reflejo la gestion concurrente';
      end if;

      begin
        perform crm.revertir_derivacion_equipo_fn(${sqlLiteral(context.leadId)}::uuid);
        raise exception 'C04 la devolucion acepto una gestion concurrente'
          using errcode = 'P0099';
      exception
        when sqlstate 'P0001' then
          get stacked diagnostics v_mensaje = message_text;
          if v_mensaje not like '%registró gestión%' then
            raise exception 'C05 la devolucion fallo por otra causa: %', v_mensaje;
          end if;
      end;
    end;
    $sonda$;
  `);

  return runPsql('leer evidencia causal', `
    select pg_catalog.concat_ws(
      '|',
      (activity.metadata->>'statement_started_at')::timestamptz::text,
      assignment.asignado_en::text,
      activity.creado_en::text
    )
    from crm.lead_asignaciones assignment
    join crm.actividades activity
      on activity.lead_id = assignment.lead_id
    where assignment.lead_id = ${sqlLiteral(context.leadId)}::uuid
      and assignment.analista_id = ${sqlLiteral(context.analystId)}::uuid
      and activity.detalle = ${sqlLiteral(context.marker)}
    order by assignment.asignado_en desc, activity.creado_en desc
    limit 1;
  `);
}

async function cleanupScenario(context) {
  const raw = await runPsql('cleanup exclusivo de sonda y verificacion global', `
    begin;
    set local session_replication_role = replica;

    create temporary table gcar_probe_tasks on commit drop as
    select task.id
    from crm.tareas task
    where task.lead_id = ${sqlLiteral(context.leadId)}::uuid
       or task.id = ${sqlLiteral(context.taskId)}::uuid;

    create temporary table gcar_probe_activities on commit drop as
    select activity.id
    from crm.actividades activity
    where activity.lead_id = ${sqlLiteral(context.leadId)}::uuid;

    create temporary table gcar_probe_assignments on commit drop as
    select assignment.id
    from crm.lead_asignaciones assignment
    where assignment.lead_id = ${sqlLiteral(context.leadId)}::uuid;

    create temporary table gcar_probe_milestones on commit drop as
    select milestone.id
    from crm.lead_asignacion_sla_hitos milestone
    join gcar_probe_assignments assignment
      on assignment.id = milestone.lead_asignacion_id;

    create temporary table gcar_probe_client_activities on commit drop as
    select activity.id
    from crm.actividades_cliente activity
    join gcar_probe_tasks task on task.id = activity.tarea_id;

    create temporary table gcar_probe_audit on commit drop as
    select audit.id
    from public.audit_log audit
    where (audit.tabla = 'crm.leads'
          and audit.fila_id = ${sqlLiteral(context.leadId)})
       or coalesce(
            audit.data_despues->>'lead_id',
            audit.data_antes->>'lead_id'
          ) = ${sqlLiteral(context.leadId)}
       or (
         audit.tabla = 'crm.actividades_cliente'
         and coalesce(
           audit.data_despues->>'tarea_id',
           audit.data_antes->>'tarea_id'
         ) in (select task.id::text from gcar_probe_tasks task)
       )
       or (
         audit.tabla = 'crm.lead_asignacion_sla_hitos'
         and coalesce(
           audit.data_despues->>'lead_asignacion_id',
           audit.data_antes->>'lead_asignacion_id'
         ) in (select assignment.id::text from gcar_probe_assignments assignment)
       )
       or (
         audit.tabla = 'crm.tareas'
         and audit.fila_id in (select task.id::text from gcar_probe_tasks task)
       )
       or (
         audit.tabla = 'crm.actividades'
         and audit.fila_id in (select activity.id::text from gcar_probe_activities activity)
       )
       or (
         audit.tabla = 'crm.lead_asignaciones'
         and audit.fila_id in (select assignment.id::text from gcar_probe_assignments assignment)
       )
       or (
         audit.tabla = 'crm.lead_asignacion_sla_hitos'
         and audit.fila_id in (select milestone.id::text from gcar_probe_milestones milestone)
       );

    delete from public.audit_log audit
    where audit.id in (select target.id from gcar_probe_audit target);

    delete from crm.actividades_cliente activity
    where activity.id in (select target.id from gcar_probe_client_activities target);

    delete from crm.lead_asignacion_sla_hitos milestone
    where milestone.id in (select target.id from gcar_probe_milestones target);

    delete from crm.lead_sla_etapas stage
    where stage.lead_id = ${sqlLiteral(context.leadId)}::uuid;

    delete from crm.lead_sla_ciclos cycle
    where cycle.lead_id = ${sqlLiteral(context.leadId)}::uuid;

    delete from crm.ajustes_mes_cerrado adjustment
    where adjustment.lead_id = ${sqlLiteral(context.leadId)}::uuid;

    delete from crm.cierres_avance_anulados closure
    where closure.lead_id = ${sqlLiteral(context.leadId)}::uuid;

    delete from crm.cierres_externos closure
    where closure.lead_id = ${sqlLiteral(context.leadId)}::uuid;

    delete from crm.conversion_reservas reservation
    where reservation.lead_id = ${sqlLiteral(context.leadId)}::uuid;

    delete from crm.lead_asignaciones assignment
    where assignment.id in (select target.id from gcar_probe_assignments target);

    delete from crm.tareas task
    where task.id in (select target.id from gcar_probe_tasks target);

    delete from crm.actividades activity
    where activity.id in (select target.id from gcar_probe_activities target);

    delete from crm.leads lead
    where lead.id = ${sqlLiteral(context.leadId)}::uuid;

    set local session_replication_role = origin;

    create temporary table gcar_current_counts on commit drop as
    select ${globalCountsSql()} as value;

    select pg_catalog.jsonb_build_object(
      'baseline_matches',
        (select value from gcar_current_counts) = ${jsonbSql(context.baseline)},
      'baseline', ${jsonbSql(context.baseline)},
      'current_counts', (select value from gcar_current_counts),
      'probe_counts', pg_catalog.jsonb_build_object(
        'audit', (select count(*) from public.audit_log audit
          where audit.id in (select target.id from gcar_probe_audit target)),
        'actividades', (select count(*) from crm.actividades activity
          where activity.lead_id = ${sqlLiteral(context.leadId)}::uuid),
        'actividades_cliente', (select count(*) from crm.actividades_cliente activity
          where activity.id in (select target.id from gcar_probe_client_activities target)),
        'ajustes', (select count(*) from crm.ajustes_mes_cerrado adjustment
          where adjustment.lead_id = ${sqlLiteral(context.leadId)}::uuid),
        'cierres_anulados', (select count(*) from crm.cierres_avance_anulados closure
          where closure.lead_id = ${sqlLiteral(context.leadId)}::uuid),
        'cierres_externos', (select count(*) from crm.cierres_externos closure
          where closure.lead_id = ${sqlLiteral(context.leadId)}::uuid),
        'conversion_reservas', (select count(*) from crm.conversion_reservas reservation
          where reservation.lead_id = ${sqlLiteral(context.leadId)}::uuid),
        'hitos', (select count(*) from crm.lead_asignacion_sla_hitos milestone
          where milestone.id in (select target.id from gcar_probe_milestones target)),
        'asignaciones', (select count(*) from crm.lead_asignaciones assignment
          where assignment.lead_id = ${sqlLiteral(context.leadId)}::uuid),
        'sla_ciclos', (select count(*) from crm.lead_sla_ciclos cycle
          where cycle.lead_id = ${sqlLiteral(context.leadId)}::uuid),
        'sla_etapas', (select count(*) from crm.lead_sla_etapas stage
          where stage.lead_id = ${sqlLiteral(context.leadId)}::uuid),
        'tareas', (select count(*) from crm.tareas task
          where task.lead_id = ${sqlLiteral(context.leadId)}::uuid
             or task.id = ${sqlLiteral(context.taskId)}::uuid),
        'lead', (select count(*) from crm.leads lead
          where lead.id = ${sqlLiteral(context.leadId)}::uuid
             or lead.nombre_completo = ${sqlLiteral(context.probeName)}
             or lead.telefono = ${sqlLiteral(context.probePhone)})
      )
    )::text;
    commit;
  `);

  const state = parseJsonObject(raw, 'cleanup');
  if (!state.probe_counts
      || typeof state.probe_counts !== 'object'
      || Array.isArray(state.probe_counts)) {
    throw new Error('cleanup no devolvio los conteos de la sonda');
  }
  const residuals = Object.entries(state.probe_counts)
    .filter(([, count]) => count !== 0);
  if (residuals.length > 0) {
    throw new Error(`cleanup dejo filas de sonda: ${JSON.stringify(state.probe_counts)}`);
  }
  if (state.baseline_matches !== true) {
    throw new Error(
      'los conteos globales cambiaron fuera de la sonda; no se borro el cambio externo '
      + `(baseline=${JSON.stringify(state.baseline)}, actual=${JSON.stringify(state.current_counts)})`,
    );
  }
  return state.current_counts;
}

async function runScenario({ injectFailure }) {
  const identity = scenarioIdentity();
  const preflight = await loadPreflight();
  const context = { ...identity, ...preflight };
  const applicationPrefix = `gcar_deriv_${identity.runId.replaceAll('-', '')}`;
  const injectedFailureMessage = 'fallo inyectado tras observar pg_sleep de la sesion 1';
  let setupAttempted = false;
  let setupVerified = false;
  let session1;
  let session2;
  let causalEvidence;
  let primaryError;
  let expectedFailureObserved = false;
  let terminatedBackends = 0;
  let cleanupCounts;

  try {
    // Desde este punto el cleanup se intenta siempre: una desconexion de psql
    // despues del COMMIT podria ocultar un setup realmente persistido.
    setupAttempted = true;
    const setupState = await setupScenario(context);
    if (setupState !== '1|1') {
      throw new Error(`setup de sonda no fue exacto (lead|tarea): ${setupState || '(vacio)'}`);
    }
    setupVerified = true;

    session1 = startPsql(
      'sesion 1: gestion concurrente del analista',
      insertManagementSql(context),
      `${applicationPrefix}_s1`,
    );
    await waitForPgSleep(session1);

    if (injectFailure) {
      expectedFailureObserved = true;
      throw new Error(injectedFailureMessage);
    }

    session2 = startPsql(
      'sesion 2: derivacion del supervisor',
      deriveSql(context),
      `${applicationPrefix}_s2`,
    );
    await session2.completion;
    await session1.completion;

    causalEvidence = await verifyCausality(context);
    if (!causalEvidence || causalEvidence.split('|').length !== 3) {
      throw new Error(`evidencia causal no reconocida: ${causalEvidence || '(vacia)'}`);
    }
  } catch (error) {
    const current = asError(error);
    const expected = injectFailure
      && expectedFailureObserved
      && current.message === injectedFailureMessage;
    if (!expected) primaryError = current;
  } finally {
    const sessions = [session1, session2].filter(Boolean);
    try {
      terminatedBackends += await terminateTrackedSessions(sessions);
    } catch (error) {
      primaryError = appendError(primaryError, 'Cierre de sesiones fallo', error);
    }

    for (const session of sessions) {
      if (!session.hasExited()) session.child.kill('SIGTERM');
    }
    await Promise.allSettled(sessions.map((session) => session.completion));

    try {
      terminatedBackends += await terminateTrackedSessions(sessions);
    } catch (error) {
      primaryError = appendError(primaryError, 'Postcondicion de sesiones fallo', error);
    }

    if (setupAttempted) {
      try {
        cleanupCounts = await cleanupScenario(context);
      } catch (error) {
        primaryError = appendError(primaryError, 'Cleanup fallo', error);
      }
    }
  }

  if (injectFailure && !expectedFailureObserved) {
    primaryError = appendError(
      primaryError,
      'Fallo inyectado no observado',
      'la sesion 1 no alcanzo pg_sleep',
    );
  }
  if (injectFailure && terminatedBackends < 1) {
    primaryError = appendError(
      primaryError,
      'Fallo inyectado no ejercito la terminacion',
      'pg_terminate_backend no devolvio true para el PID real rastreado',
    );
  }
  if (!setupVerified) {
    primaryError = appendError(
      primaryError,
      'Setup no verificado',
      'psql no confirmo exactamente el lead y la tarea de sonda',
    );
  }
  if (!cleanupCounts) {
    primaryError = appendError(primaryError, 'Cleanup no verificado', 'faltan conteos globales');
  }
  if (primaryError) throw primaryError;
  return causalEvidence;
}

try {
  await runScenario({ injectFailure: true });
  console.log('REPORTE_DERIVACIONES_CONCURRENCIA_FALLO_INYECTADO_CLEANUP_OK');

  const causalEvidence = await runScenario({ injectFailure: false });
  console.log('REPORTE_DERIVACIONES_CONCURRENCIA_LOCAL_OK');
  console.log(`Orden causal inicio|asignacion|gestion: ${causalEvidence}`);
  console.log('REPORTE_DERIVACIONES_CONCURRENCIA_CLEANUP_EXACTO_OK');
  console.log('REPORTE_DERIVACIONES_CONCURRENCIA_CONTEOS_GLOBALES_OK');
} catch (error) {
  console.error(asError(error).message);
  process.exitCode = 1;
}
