#!/usr/bin/env node
// Prueba la migración REAL 20261001145242 (Llamadas desde el celular · F2-b) en un PostgreSQL
// 16/17 desechable: initdb en una carpeta temporal, escucha solo en 127.0.0.1, contraseña de usar
// y tirar generada aquí (nunca se imprime ni sale de la carpeta temporal) y se borra al terminar.
// Nunca acepta una URL ni variables PG* del entorno: este banco no puede apuntar a otro servidor.
//
// Banco reducido: supabase/tests/llamadas-celular/base.sql (auditoría, regla de rastro,
// canonización y forma del resultado reales; identidad y ámbito como dobles declarados).
// Molde: supabase/scripts/test-sla-nucleo-local.py. No sustituye el gate test-rls.mjs.
//
// Dos pasadas:
//   1. La migración tal cual: se aplica, se niega a sobrescribirse, el oráculo pasa, las dos
//      reversas funcionan (la total se niega con filas) y se vuelve a aplicar.
//   2. Mutantes: por cada defensa, una copia de la migración que la neutraliza. Un mutante «de
//      oráculo» tiene que APLICARSE y hacer fallar el oráculo; uno «de postflight» tiene que ser
//      rechazado por el propio postflight con su mensaje. Si sobrevive, esa defensa no está probada.
//
// Uso:  node supabase/scripts/test-llamadas-celular-local.mjs     (npm run test:llamadas:local)
// Binarios: LLAMADAS_PG_BIN, o ~/.local/pg/pgsql/bin (zip oficial de EDB en Windows), o Homebrew.
import { spawnSync } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const RAIZ = fileURLToPath(new URL('../..', import.meta.url));
const MIGRACION = join(RAIZ, 'supabase/migrations/20261001145242_crm_llamadas_celular_datos.sql');
const BASE = join(RAIZ, 'supabase/tests/llamadas-celular/base.sql');
const ORACULO = join(RAIZ, 'supabase/scripts/llamadas-celular/verificar-datos.sql');
const REVERSA = join(RAIZ, 'supabase/scripts/llamadas-celular/reversa-datos.sql');
const REVERSA_TOTAL = join(RAIZ, 'supabase/scripts/llamadas-celular/reversa-datos-total.sql');
const PUERTO = '55485';
const USUARIO = 'llamadas_test_owner';
const EXE = process.platform === 'win32' ? '.exe' : '';

// Cada defensa y la copia de la migración que la neutraliza. `aviso` convierte su
// `raise exception` en `raise notice` (la regla sigue escrita, pero ya no frena nada).
const MUTANTES = [
  { nombre: 'auditoría con el número a la vista', buscar: "log_audit_sin_secretos('numero_canonico', 'hash_payload')", poner: "log_audit_sin_secretos('hash_payload')" },
  { nombre: 'auditoría con el hash del payload a la vista', buscar: "log_audit_sin_secretos('numero_canonico', 'hash_payload')", poner: "log_audit_sin_secretos('numero_canonico')" },
  { nombre: 'auditoría con la credencial a la vista', buscar: "private.log_audit_sin_secretos('credencial_hash');", poner: 'private.log_audit_crm();' },
  { nombre: 'credencial que no es un sha256', buscar: "check (credencial_hash ~ '^[0-9a-f]{64}$')", poner: 'check (true)' },
  { nombre: 'DELETE de llamadas sin el GUC de la purga', buscar: "if coalesce(pg_catalog.current_setting('crm.op_purga_llamadas', true), 'off') = 'on'", poner: 'if true' },
  { nombre: 'payload editable', aviso: 'El contenido de una llamada del celular es inmutable' },
  { nombre: 'identificación que retrocede', aviso: 'La identificación de una llamada solo avanza' },
  { nombre: 'lead de una llamada registrada editable', aviso: 'Una llamada registrada o descartada no cambia de lead' },
  { nombre: 'transiciones de atención libres', aviso: 'Transición no permitida de la llamada' },
  { nombre: 'motivo de descarte reescribible', aviso: 'El motivo de un descarte no se reescribe' },
  { nombre: 'devolución pedida para una saliente', buscar: "and identificacion = 'identificado' and direccion = 'entrante')", poner: "and identificacion = 'identificado')" },
  { nombre: 'asociación manual sin autor', buscar: "or metodo_asociacion = 'exacto' or asociado_por is not null)", poner: 'or true)' },
  { nombre: 'descarte «otro» sin detalle', buscar: '>= 3))', poner: '>= 0))' },
  { nombre: 'enlace movible sin deshacer el resultado', buscar: 'if not coalesce(v_deshecha, false) then', poner: 'if false then' },
  { nombre: 'enlace desenlazable', aviso: 'Un enlace no se desenlaza' },
  { nombre: 'enlace a una actividad de otro lead', aviso: 'La actividad enlazada es de otro lead' },
  { nombre: 'enlace con lead distinto al de la llamada', aviso: 'El enlace debe apuntar al lead de la llamada' },
  { nombre: 'enlace a algo que no es un resultado de llamada', aviso: 'Solo se enlaza un resultado de llamada' },
  { nombre: 'enlace sin actividad', aviso: 'Un enlace nace con la actividad registrada' },
  { nombre: 'enlace borrable', aviso: 'El enlace de una llamada no se borra' },
  { nombre: 'asignación borrable', aviso: 'Una asignación de celular no se borra' },
  { nombre: 'asignación cerrada editable', aviso: 'Una asignación de celular cerrada es inmutable' },
  { nombre: 'asignación con analista editable', aviso: 'De una asignación de celular solo se cierra la vigencia' },
  { nombre: 'política borrable', aviso: 'La política de llamadas no se borra' },
  { nombre: 'tablas vaciables', aviso: '%s no se vacía: es evidencia de llamadas' },
  { nombre: 'purga sin plazo para descartadas', buscar: '\n     and e.descartado_en < pg_catalog.now() - pg_catalog.make_interval(days => v_pol.dias_retencion_descartados);', poner: ';' },
  { nombre: 'purga que deja el GUC encendido', buscar: "  perform pg_catalog.set_config('crm.op_purga_llamadas', 'off', true);\n", poner: '' },
  { nombre: 'sin exclusión de vigencias', por: 'postflight', espera: 'falta la exclusión',
    buscar: "exclude using gist (\n      etiqueta with =,\n      tstzrange(vigente_desde, coalesce(vigente_hasta, 'infinity'::timestamptz), '[)') with &&\n    )", poner: 'check (true)' },
  { nombre: 'RLS apagada en eventos', por: 'postflight', espera: 'quedó sin RLS',
    buscar: 'alter table crm.llamadas_celular_eventos enable row level security;\n', poner: '' },
  { nombre: 'enlaces abiertos a la API', por: 'postflight', espera: 'accesible desde la API',
    buscar: 'revoke all on crm.llamadas_celular_enlaces from public, anon, authenticated, service_role;', poner: 'grant select on crm.llamadas_celular_enlaces to authenticated;' },
  { nombre: 'autoría que se desatribuye (SET NULL)', por: 'postflight', espera: 'no es RESTRICT',
    buscar: 'descartado_por          uuid references public.perfiles(id) on delete restrict,', poner: 'descartado_por          uuid references public.perfiles(id) on delete set null,' },
  { nombre: 'FK sin índice', por: 'postflight', espera: 'sin índice que la cubra',
    buscar: 'create index llamadas_celular_eventos_descartado_por_idx\n  on crm.llamadas_celular_eventos (descartado_por);\n', poner: '' },
];

function carpetaBinarios() {
  const candidatos = [
    process.env.LLAMADAS_PG_BIN,
    join(homedir(), '.local/pg/pgsql/bin'),
    '/opt/homebrew/opt/postgresql@17/bin',
    '/opt/homebrew/opt/postgresql@16/bin',
    '/usr/lib/postgresql/17/bin',
    '/usr/lib/postgresql/16/bin',
  ].filter(Boolean);
  for (const dir of candidatos) if (existsSync(join(dir, `initdb${EXE}`))) return dir;
  throw new Error('No encuentro PostgreSQL 16/17: define LLAMADAS_PG_BIN con la carpeta de initdb');
}

const PG = carpetaBinarios();
const temporal = mkdtempSync(join(tmpdir(), 'llamadas-celular-'));
const datos = join(temporal, 'data');
const bitacora = join(temporal, 'postgres.log');
const clave = randomBytes(18).toString('hex');
const archivoClave = join(temporal, 'clave');
writeFileSync(archivoClave, `${clave}\n`, { mode: 0o600 });

// Fuera toda variable PG* heredada: el destino lo fija este guion y nada más.
const env = Object.fromEntries(Object.entries(process.env).filter(([k]) => !k.startsWith('PG')));
Object.assign(env, {
  PGHOST: '127.0.0.1', PGPORT: PUERTO, PGUSER: USUARIO,
  PGPASSWORD: clave, PGCONNECT_TIMEOUT: '5', PGTZ: 'UTC',
});

// `sinTuberias`: el servidor que lanza pg_ctl heredaría las tuberías de salida y, en Windows,
// spawnSync esperaría hasta su timeout. Su salida ya va a la bitácora (-l).
function correr(binario, args, { sinTuberias = false } = {}) {
  const r = spawnSync(join(PG, binario + EXE), args, {
    env, encoding: 'utf8', timeout: 180_000, ...(sinTuberias ? { stdio: 'ignore' } : {}),
  });
  const salida = `${r.stdout ?? ''}${r.stderr ?? ''}`.split(clave).join('<clave>');
  return { ok: r.status === 0 && !r.error, salida: salida || (r.error ? String(r.error.message) : '') };
}
const psqlArchivo = (archivo, db) => correr('psql', ['-X', '-q', '-v', 'ON_ERROR_STOP=1', '-d', db, '-f', archivo]);
const psqlSql = (sql, db) => correr('psql', ['-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-d', db, '-c', sql]);
const cola = (texto, n = 700) => texto.trim().slice(-n);
const lineasOraculo = (texto) => (texto.match(/ORACULO[^\n]*/g) ?? [cola(texto)]).join('\n');

const pasos = [];
function paso(nombre, ok, detalle = '') {
  pasos.push({ nombre, ok: Boolean(ok) });
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${nombre}${detalle ? `\n      ${detalle.replace(/\n/g, '\n      ')}` : ''}`);
  return Boolean(ok);
}

function escaparRegex(texto) {
  return texto.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}
function aplicarMutante(original, mutante) {
  if (mutante.aviso) {
    const patron = new RegExp(
      `raise exception using errcode = '[0-9A-Z]{5}',(\\s*message = (?:pg_catalog\\.format\\()?'${escaparRegex(mutante.aviso)})`, 'g');
    const encontrados = original.match(patron) ?? [];
    if (encontrados.length !== 1) return { error: `el aviso aparece ${encontrados.length} veces` };
    return { texto: original.replace(patron, 'raise notice using$1') };
  }
  const veces = original.split(mutante.buscar).length - 1;
  if (veces !== 1) return { error: `el fragmento aparece ${veces} veces` };
  return { texto: original.replace(mutante.buscar, mutante.poner) };
}

let arrancado = false;
try {
  const init = correr('initdb', ['-D', datos, '-U', USUARIO, '-A', 'scram-sha-256', '--pwfile', archivoClave,
    '--no-locale', '-E', 'UTF8']);
  if (!init.ok) throw new Error(`initdb falló:\n${cola(init.salida)}`);
  const inicio = correr('pg_ctl', ['-D', datos, '-l', bitacora, '-w', '-t', '60',
    '-o', `-c listen_addresses=127.0.0.1 -p ${PUERTO} -c fsync=off -c timezone=UTC`, 'start'], { sinTuberias: true });
  if (!inicio.ok) {
    const log = existsSync(bitacora) ? readFileSync(bitacora, 'utf8') : '';
    throw new Error(`pg_ctl start falló:\n${cola(inicio.salida)}\n${cola(log)}`);
  }
  arrancado = true;
  const version = psqlSql('show server_version', 'postgres');
  console.log(`Banco desechable: PostgreSQL ${version.salida.trim()} en 127.0.0.1:${PUERTO} (se borra al terminar)\n`);

  // Plantilla con el banco reducido: cada pasada clona la suya.
  let r = psqlSql('create database plantilla', 'postgres');
  if (!r.ok) throw new Error(`no se pudo crear la plantilla:\n${cola(r.salida)}`);
  r = psqlArchivo(BASE, 'plantilla');
  paso('banco reducido sembrado', r.ok, r.ok ? '' : cola(r.salida));
  if (!r.ok) throw new Error('sin banco reducido no hay pruebas');
  psqlSql('create database principal template plantilla', 'postgres');

  console.log('\n— Pasada 1: la migración tal cual —');
  r = psqlArchivo(MIGRACION, 'principal');
  paso('migración aplicada (precondición, tablas, candados, purga, postflight)', r.ok, cola(r.salida, r.ok ? 300 : 800));
  r = psqlArchivo(MIGRACION, 'principal');
  paso('reaplicarla se niega a sobrescribir', !r.ok && r.salida.includes('los objetos ya existen'), r.ok ? 'se aplicó dos veces' : '');
  r = psqlArchivo(ORACULO, 'principal');
  paso('oráculo de la migración', r.ok && r.salida.includes('ORACULO F2-b OK'), lineasOraculo(r.salida));
  r = psqlSql('select count(*) from crm.llamadas_celular_eventos', 'principal');
  paso('el oráculo no dejó filas (termina en ROLLBACK)', r.ok && r.salida.trim() === '0', r.salida.trim());
  r = psqlArchivo(REVERSA, 'principal');
  paso('reversa que conserva los hechos', r.ok, r.ok ? '' : cola(r.salida));
  r = psqlSql('select count(*) from crm.llamadas_celular_politica', 'principal');
  paso('tras esa reversa las tablas siguen (política con 1 fila)', r.ok && r.salida.trim() === '1', r.salida.trim());
  r = psqlSql("insert into crm.celulares_asignaciones (etiqueta, analista_id, credencial_hash) "
    + "select 'C9', e.perfil_id, repeat('e', 64) from crm.equipo e where e.rol_crm = 'vendedor' order by e.perfil_id limit 1", 'principal');
  paso('fila de prueba para la reversa total', r.ok, r.ok ? '' : cola(r.salida));
  r = psqlArchivo(REVERSA_TOTAL, 'principal');
  paso('reversa total se niega si hay filas', !r.ok && r.salida.includes('la evidencia no se borra'), r.ok ? 'borró con filas' : '');
  r = psqlSql("delete from crm.celulares_asignaciones where etiqueta = 'C9'", 'principal');
  paso('fila de prueba retirada', r.ok, r.ok ? '' : cola(r.salida));
  r = psqlArchivo(REVERSA_TOTAL, 'principal');
  paso('reversa total sin filas', r.ok, r.ok ? '' : cola(r.salida));
  r = psqlArchivo(MIGRACION, 'principal');
  paso('la migración se vuelve a aplicar tras la reversa total', r.ok, r.ok ? '' : cola(r.salida));
  r = psqlArchivo(ORACULO, 'principal');
  paso('oráculo tras reaplicar', r.ok && r.salida.includes('ORACULO F2-b OK'), lineasOraculo(r.salida));

  console.log('\n— Pasada 2: mutantes (cada uno neutraliza una defensa) —');
  const original = readFileSync(MIGRACION, 'utf8').replace(/\r\n/g, '\n');
  MUTANTES.forEach((mutante, i) => {
    const etiqueta = `mutante ${String(i + 1).padStart(2, '0')}: ${mutante.nombre}`;
    const m = aplicarMutante(original, mutante);
    if (m.error) { paso(etiqueta, false, `mutante obsoleto: ${m.error}`); return; }
    const archivo = join(temporal, `mutante-${i + 1}.sql`);
    writeFileSync(archivo, m.texto);
    const db = `mutante_${i + 1}`;
    psqlSql(`create database ${db} template plantilla`, 'postgres');
    const aplicado = psqlArchivo(archivo, db);
    if (mutante.por === 'postflight') {
      paso(etiqueta, !aplicado.ok && aplicado.salida.includes(mutante.espera),
        aplicado.ok ? 'SOBREVIVE: la migración mutada se aplicó' : `cazado por el postflight: ${lineaError(aplicado.salida)}`);
    } else if (!aplicado.ok) {
      paso(etiqueta, false, `la migración mutada no se aplica (mutante inválido): ${lineaError(aplicado.salida)}`);
    } else {
      const oraculo = psqlArchivo(ORACULO, db);
      paso(etiqueta, !oraculo.ok,
        oraculo.ok ? 'SOBREVIVE: el oráculo no lo nota' : `cazado por el oráculo: ${lineaError(oraculo.salida)}`);
    }
    psqlSql(`drop database ${db}`, 'postgres');
  });
} catch (error) {
  paso('arranque del banco', false, error.message);
} finally {
  if (arrancado) correr('pg_ctl', ['-D', datos, '-m', 'fast', '-w', 'stop'], { sinTuberias: true });
  try { rmSync(temporal, { recursive: true, force: true }); } catch { /* carpeta temporal */ }
}

function lineaError(texto) {
  const linea = texto.split('\n').find((l) => /ERROR:/.test(l)) ?? cola(texto, 200);
  return linea.replace(/^.*ERROR:\s*/, '').slice(0, 160);
}

const fallos = pasos.filter((p) => !p.ok).length;
console.log(fallos ? `\n${fallos} de ${pasos.length} pasos FALLARON` : `\nTODO EN VERDE: ${pasos.length} pasos`);
process.exit(fallos ? 1 : 0);
