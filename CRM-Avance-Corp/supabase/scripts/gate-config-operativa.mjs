#!/usr/bin/env node

import { randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const PROJECT_ROOT = fileURLToPath(new URL('../..', import.meta.url));
const REPO_ROOT = fileURLToPath(new URL('../../..', import.meta.url));
const PSQL = process.env.PSQL_BIN?.trim() || 'psql';
const DENO = process.env.DENO_BIN?.trim() || 'deno';

const HELP = `Gate reproducible de Configuración operativa

Uso:
  npm run gate:config:preflight
  CRM_CONFIG_GATE_TEMPLATE_DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/prod_schema_chain' npm run gate:config

Modos:
  --preflight  Valida contratos de los oráculos, espejo Edge y ejecuta 19 pruebas
               Deno puras. No abre PostgreSQL.
  --help       Muestra esta ayuda.

Ejecución SQL:
  CRM_CONFIG_GATE_TEMPLATE_DATABASE_URL debe apuntar a una base LOCAL,
  desechable y anterior a 203740, en un cluster donde el actor pueda crear y
  borrar bases. El runner nunca escribe en esa plantilla: crea cuatro clones
  con nombres aleatorios, completa únicamente el stub estándar de auth.users,
  aplica 203740 -> 203751 -> 203757 -> 235933 -> 183527 donde corresponde,
  exige los cinco tokens y elimina los clones incluso si una aserción falla.

Opcionales:
  CRM_CONFIG_GATE_MAINTENANCE_DATABASE  Base de mantenimiento (default: postgres)
  PSQL_BIN                             Binario psql (default: psql)
  DENO_BIN                             Binario deno (default: deno)
`;

const args = new Set(process.argv.slice(2));
const allowedArgs = new Set(['--preflight', '--help', '-h']);
const unknownArgs = [...args].filter((arg) => !allowedArgs.has(arg));
if (unknownArgs.length > 0) fail(`Opciones desconocidas: ${unknownArgs.join(', ')}`);
if (args.has('--help') || args.has('-h')) {
  console.log(HELP);
  process.exit(0);
}

const preflight = args.has('--preflight');

const MIGRATIONS = [
  'supabase/migrations/20260807203740_crm_usuarios_jerarquia_autoservicio.sql',
  'supabase/migrations/20260807203751_crm_catalogo_productos_versionado.sql',
  'supabase/migrations/20260807203757_crm_metas_sla_versionados.sql',
  'supabase/migrations/20260807235933_crm_portal_catalogo_productos.sql',
  'supabase/migrations/20260808183527_crm_metas_contratos_libres_atribuidos.sql',
  'supabase/migrations/20260821212628_crm_admision_analista_portal_como_candidato.sql',
  'supabase/migrations/20260821214502_crm_corregir_validacion_correo_candidato.sql',
  'supabase/migrations/20260821223019_crm_eliminar_recuperacion_credenciales.sql',
  'supabase/migrations/20260821233241_crm_alta_vendedor_completa_gerencia.sql',
];

const ORACLES = Object.freeze({
  usuarios: {
    file: 'supabase/scripts/test-usuarios-jerarquia.sql',
    token: 'USUARIOS_JERARQUIA_TX_OK',
  },
  productos: {
    file: 'supabase/scripts/test-productos-inversion.sql',
    token: 'PRODUCTOS_INVERSION_TX_OK',
  },
  metas: {
    file: 'supabase/scripts/test-metas-versionadas.sql',
    token: 'METAS_VERSIONADAS_TX_OK',
  },
  sla: {
    file: 'supabase/scripts/test-sla-versionado.sql',
    token: 'SLA_VERSIONADO_TX_OK',
  },
  distribucion: {
    file: 'supabase/scripts/test-metricas-distribucion-leads.sql',
    token: 'METRICAS_DISTRIBUCION_TX_OK',
  },
});

function fail(message) {
  console.error(`ERROR: ${message}`);
  process.exit(1);
}

function qIdent(value) {
  if (!value || value.includes('\0')) throw new Error('Identificador PostgreSQL inválido');
  return `"${value.replaceAll('"', '""')}"`;
}

function absolute(relative) {
  return `${PROJECT_ROOT}/${relative}`;
}

function file(relative) {
  try {
    return readFileSync(absolute(relative));
  } catch (error) {
    throw new Error(`No se pudo leer ${relative}: ${error.message}`);
  }
}

function run(label, command, commandArgs, options = {}) {
  console.log(`\n▶ ${label}`);
  const result = spawnSync(command, commandArgs, {
    cwd: PROJECT_ROOT,
    encoding: 'utf8',
    timeout: options.timeout ?? 180_000,
    maxBuffer: 32 * 1024 * 1024,
    env: process.env,
  });
  if (result.error) throw new Error(`${label}: ${result.error.message}`);
  if (result.status !== 0) {
    const output = `${result.stdout ?? ''}${result.stderr ?? ''}`.trim();
    throw new Error(`${label} terminó con código ${String(result.status)}${output ? `\n${output}` : ''}`);
  }
  const output = `${result.stdout ?? ''}${result.stderr ?? ''}`;
  if (options.showOutput && output.trim()) console.log(output.trim());
  return output;
}

function verifyStaticContracts() {
  for (const migration of MIGRATIONS) file(migration);

  for (const [name, oracle] of Object.entries(ORACLES)) {
    const source = file(oracle.file).toString('utf8');
    if (!source.includes(oracle.token)) {
      throw new Error(`${oracle.file} no contiene el token ${oracle.token}`);
    }
    if (name !== 'distribucion' && !/^\\set ON_ERROR_STOP on\s*$/m.test(source)) {
      throw new Error(`${oracle.file} no activa ON_ERROR_STOP`);
    }
  }

  const mirrors = ['index.ts', 'destinos.ts', 'resultado-importacion.ts'];
  for (const name of mirrors) {
    const canonical = file(`supabase/functions/crm-importar-leads/${name}`);
    const deployed = readFileSync(`${REPO_ROOT}/_supabase_functions/functions/crm-importar-leads/${name}`);
    if (!canonical.equals(deployed)) {
      throw new Error(`Drift Edge: crm-importar-leads/${name} difiere de su espejo operativo`);
    }
  }
  console.log('✓ contratos estáticos, cinco tokens y espejo Edge exacto');
}

function runEdgeTests() {
  const output = run('Pruebas Edge puras', DENO, [
    'test',
    'supabase/functions/crm-usuarios/handler.test.ts',
    'supabase/functions/crm-usuarios/auth-attributes.test.ts',
    'supabase/functions/crm-importar-leads/destinos.test.ts',
    'supabase/functions/crm-importar-leads/resultado-importacion.test.ts',
  ]);
  if (!/25 passed/.test(output)) {
    throw new Error('Deno terminó sin acreditar las 25 pruebas Edge esperadas');
  }
  console.log('✓ EDGE_CONFIG_TESTS_OK (25/25)');
}

function parseTemplateUrl(raw) {
  let url;
  try {
    url = new URL(raw);
  } catch {
    throw new Error('CRM_CONFIG_GATE_TEMPLATE_DATABASE_URL no es una URL PostgreSQL válida');
  }
  if (!['postgres:', 'postgresql:'].includes(url.protocol)) {
    throw new Error('La plantilla debe usar postgresql://');
  }
  const socketHost = url.searchParams.get('host');
  const localTcp = ['localhost', '127.0.0.1', '[::1]', '::1'].includes(url.hostname);
  const localSocket = url.hostname === '' && socketHost?.startsWith('/');
  if (!localTcp && !localSocket) {
    throw new Error('El gate SQL solo acepta PostgreSQL local o socket Unix; nunca una base remota');
  }
  const database = decodeURIComponent(url.pathname.replace(/^\//, ''));
  if (!database) throw new Error('La URL debe incluir la base plantilla');
  return { url, database };
}

function databaseUrl(base, database) {
  const result = new URL(base);
  result.pathname = `/${encodeURIComponent(database)}`;
  return result.toString();
}

function psql(url, commandArgs, label, options = {}) {
  return run(label, PSQL, [
    '-X',
    '-v', 'ON_ERROR_STOP=1',
    '--dbname', url,
    ...commandArgs,
  ], options);
}

function createDatabase(maintenanceUrl, name, template) {
  psql(
    maintenanceUrl,
    ['-c', `create database ${qIdent(name)} template ${qIdent(template)}`],
    `Crear clon ${name}`,
  );
}

function dropDatabase(maintenanceUrl, name) {
  psql(
    maintenanceUrl,
    ['-c', `drop database if exists ${qIdent(name)} with (force)`],
    `Eliminar clon ${name}`,
  );
}

function runSqlFile(url, relative, label) {
  return psql(url, ['-f', absolute(relative)], label);
}

function runOracle(url, oracle, label) {
  const output = runSqlFile(url, oracle.file, label);
  if (!output.includes(oracle.token)) {
    throw new Error(`${label} terminó sin token ${oracle.token}`);
  }
  console.log(`✓ ${oracle.token}`);
}

const AUTH_USERS_STUB = `
alter table auth.users
  add column if not exists aud text,
  add column if not exists role text,
  add column if not exists email text,
  add column if not exists email_confirmed_at timestamptz,
  add column if not exists raw_app_meta_data jsonb,
  add column if not exists raw_user_meta_data jsonb,
  add column if not exists created_at timestamptz,
  add column if not exists updated_at timestamptz;
`;

function validateTemplate(templateUrl) {
  const output = psql(templateUrl, [
    '-Atc',
    `select
      to_regclass('public.perfiles') is not null
      and to_regclass('crm.equipo') is not null
      and to_regclass('crm.leads') is not null
      and to_regprocedure('crm.usuarios_administrables_fn(text,integer,integer)') is null
      and to_regclass('crm.meta_periodos') is null;`,
  ], 'Validar plantilla anterior a 203740');
  if (output.trim() !== 't') {
    throw new Error('La plantilla no contiene el esquema base esperado o ya recibió Configuración operativa');
  }
}

function applyConfigChain(url, label) {
  psql(url, ['-c', AUTH_USERS_STUB], `${label}: completar stub auth.users`);
  for (const migration of MIGRATIONS) {
    runSqlFile(url, migration, `${label}: aplicar ${migration.split('/').at(-1)}`);
  }
}

function runSqlGate() {
  const raw = process.env.CRM_CONFIG_GATE_TEMPLATE_DATABASE_URL?.trim();
  if (!raw) {
    throw new Error('Falta CRM_CONFIG_GATE_TEMPLATE_DATABASE_URL; usa --preflight si no tienes PostgreSQL desechable');
  }
  const template = parseTemplateUrl(raw);
  validateTemplate(template.url.toString());

  const maintenanceDatabase = process.env.CRM_CONFIG_GATE_MAINTENANCE_DATABASE?.trim() || 'postgres';
  const maintenanceUrl = databaseUrl(template.url, maintenanceDatabase);
  const suffix = `${process.pid}_${randomUUID().replaceAll('-', '').slice(0, 8)}`;
  const names = {
    usuarios: `cfg_users_${suffix}`,
    productos: `cfg_products_${suffix}`,
    metas: `cfg_goals_${suffix}`,
    sla: `cfg_sla_${suffix}`,
  };
  const created = [];

  try {
    createDatabase(maintenanceUrl, names.usuarios, 'template0');
    created.push(names.usuarios);
    createDatabase(maintenanceUrl, names.productos, 'template0');
    created.push(names.productos);
    createDatabase(maintenanceUrl, names.metas, template.database);
    created.push(names.metas);
    createDatabase(maintenanceUrl, names.sla, template.database);
    created.push(names.sla);

    const urls = Object.fromEntries(
      Object.entries(names).map(([key, name]) => [key, databaseUrl(template.url, name)]),
    );

    runOracle(urls.usuarios, ORACLES.usuarios, 'Oráculo Usuarios/Jerarquía');
    runOracle(urls.productos, ORACLES.productos, 'Oráculo Productos');

    applyConfigChain(urls.metas, 'Clon Metas');
    runOracle(urls.metas, ORACLES.metas, 'Oráculo Metas');

    applyConfigChain(urls.sla, 'Clon SLA');
    runOracle(urls.sla, ORACLES.sla, 'Oráculo SLA');
    runOracle(urls.sla, ORACLES.distribucion, 'Regresión Distribución sin SLA fijo');
  } finally {
    for (const name of created.reverse()) {
      try {
        dropDatabase(maintenanceUrl, name);
      } catch (error) {
        console.error(`ADVERTENCIA: ${error.message}`);
      }
    }
  }
}

try {
  verifyStaticContracts();
  runEdgeTests();
  if (preflight) {
    console.log('\nCONFIG_OPERATIVA_PREFLIGHT_OK');
  } else {
    runSqlGate();
    console.log('\nCONFIG_OPERATIVA_GATE_OK');
  }
} catch (error) {
  fail(error instanceof Error ? error.message : String(error));
}
