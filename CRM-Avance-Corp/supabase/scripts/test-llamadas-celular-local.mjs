#!/usr/bin/env node
// Prueba las migraciones REALES de Llamadas desde el celular (F2-b datos 20261001145242 y F2-c
// núcleo 20261001160219) en un PostgreSQL 16/17 desechable: initdb en una carpeta temporal,
// escucha solo en 127.0.0.1, contraseña de usar y tirar generada aquí (nunca se imprime ni sale de
// la carpeta temporal) y se borra al terminar. Nunca acepta una URL ni variables PG* del entorno.
//
// Banco reducido: supabase/tests/llamadas-celular/base.sql (auditoría, regla de rastro, ámbito,
// canonización, idempotencia y forma del resultado reales; auth.uid como doble declarado).
// Molde: supabase/scripts/test-sla-nucleo-local.py. No sustituye el gate test-rls.mjs.
//
// Tres pasadas:
//   1. Las migraciones tal cual: se aplican, se niegan a sobrescribirse, pasan sus oráculos, sus
//      reversas funcionan en orden (y se niegan fuera de orden o con filas) y se vuelven a aplicar.
//   2. Mutantes de F2-b y 3. mutantes de F2-c: por cada defensa, una copia de la migración que la
//      neutraliza. Un mutante «de oráculo» tiene que APLICARSE y hacer fallar su oráculo; uno «de
//      postflight» tiene que ser rechazado por el postflight con su mensaje. Si sobrevive, esa
//      defensa no está probada.
//   4. Concurrencia con dos sesiones REALES: la primera abre su transacción y la retiene; la
//      segunda llega mientras tanto, tiene que ESPERAR (se mide) y responder bien al soltarse.
//
// Uso:  node supabase/scripts/test-llamadas-celular-local.mjs     (npm run test:llamadas:local)
// Binarios: LLAMADAS_PG_BIN, o ~/.local/pg/pgsql/bin (zip oficial de EDB en Windows), o Homebrew.
import { spawn, spawnSync } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const RAIZ = fileURLToPath(new URL('../..', import.meta.url));
const MIG_DATOS = join(RAIZ, 'supabase/migrations/20261001145242_crm_llamadas_celular_datos.sql');
const MIG_NUCLEO = join(RAIZ, 'supabase/migrations/20261001160219_crm_llamadas_celular_nucleo.sql');
const BASE = join(RAIZ, 'supabase/tests/llamadas-celular/base.sql');
const ORACULO_DATOS = join(RAIZ, 'supabase/scripts/llamadas-celular/verificar-datos.sql');
const ORACULO_NUCLEO = join(RAIZ, 'supabase/tests/llamadas-celular/oraculo-nucleo.sql');
const REVERSA_DATOS = join(RAIZ, 'supabase/scripts/llamadas-celular/reversa-datos.sql');
const REVERSA_TOTAL = join(RAIZ, 'supabase/scripts/llamadas-celular/reversa-datos-total.sql');
const REVERSA_NUCLEO = join(RAIZ, 'supabase/scripts/llamadas-celular/reversa-nucleo.sql');
const PUERTO = '55485';
const USUARIO = 'llamadas_test_owner';
const EXE = process.platform === 'win32' ? '.exe' : '';

// Cada defensa y la copia de la migración que la neutraliza. `aviso` convierte su
// `raise exception` en `raise notice` (la regla sigue escrita, pero ya no frena nada);
// `ocurrencia`/`total` eligen cuál de varias iguales; `cambios` aplica varias a la vez.
const MUTANTES_DATOS = [
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

const AMBITO = 'Llamada no encontrada o fuera de tu ámbito';
const MUTANTES_NUCLEO = [
  { nombre: 'asociar sin exigir el número de la llamada', aviso: 'Ese lead no tiene el número de la llamada' },
  { nombre: 'asociar a un lead fuera de ámbito', aviso: 'Ese lead no es de tu ámbito' },
  { nombre: 'asociar una llamada que no se ve', aviso: AMBITO, ocurrencia: 1, total: 4 },
  { nombre: 'enlazar sin ámbito (decisión 7)', aviso: AMBITO, ocurrencia: 2, total: 4 },
  { nombre: 'descartar sin ámbito', aviso: AMBITO, ocurrencia: 3, total: 4 },
  { nombre: 'detalle sin ámbito', aviso: AMBITO, ocurrencia: 4, total: 4 },
  { nombre: 'reenvío con otro contenido aceptado', aviso: 'Esta llamada ya llegó con otro contenido' },
  { nombre: 'celular cerrado o analista de baja ingiere', aviso: 'Celular sin asignación vigente o analista inactivo' },
  { nombre: 'entrante guardada con la perilla apagada', buscar: "if v_dir = 'entrante' and not coalesce(v_pol.entrantes_activas, false) then", poner: 'if false then' },
  { nombre: 'número sin lead guardado con la perilla apagada', buscar: 'elsif coalesce(v_pol.guardar_sin_identificar, false) then', poner: 'elsif true then' },
  { nombre: 'hora sin normalizar en el hash', buscar: `'ocurrio_en', pg_catalog.to_char(v_ocurrio at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')`, poner: "'ocurrio_en', v_ocurrio" },
  { nombre: 'enlace con un resultado anterior a la llamada', aviso: 'El resultado se registró antes de la llamada' },
  { nombre: 'resultado vigente reemplazado', buscar: 'if v_enl.actividad_id is not null and not coalesce(v_deshecha, false) then', poner: 'if false then' },
  { nombre: 'enlace a una llamada descartada', aviso: 'La llamada fue descartada' },
  { nombre: 'enlace a una llamada sin lead', aviso: 'Primero asocia la llamada a un lead' },
  { nombre: 'descarte reescrito con otro motivo', aviso: 'La llamada ya fue descartada con otro motivo' },
  { nombre: 'bandeja sin filtro de ámbito', buscar: '\n      and private.llamada_celular_visible(p_actor, e.lead_id, e.analista_id)\n    order by e.recibido_en desc', poner: '\n    order by e.recibido_en desc' },
  { nombre: 'atención efectiva sin re-evaluar la elegibilidad', buscar: "when p_atencion = 'requiere_resultado' and private.llamada_celular_elegible(p_actor, p_lead)", poner: "when p_atencion = 'requiere_resultado'" },
  { nombre: 'credencial guardada en claro', buscar: 'values (p_etiqueta, p_analista_id, private.celular_credencial_hash(v_credencial), pg_catalog.clock_timestamp(), p_actor)', poner: 'values (p_etiqueta, p_analista_id, v_credencial, pg_catalog.clock_timestamp(), p_actor)' },
  { nombre: 'un analista asigna celulares (puerta y núcleo)', cambios: [
    { buscar: "  v_actor uuid := private.llamadas_celular_actor(array['gerencia']);\nbegin\n  return private.celular_asignar(", poner: "  v_actor uuid := private.llamadas_celular_actor(array['vendedor', 'supervisor', 'gerencia']);\nbegin\n  return private.celular_asignar(" },
    { aviso: 'Solo gerencia asigna celulares' }] },
  { nombre: 'supervisión ve celulares de otro equipo', buscar: '         and a.analista_id in (select private.vendedor_ids_visibles(p_actor)))', poner: '         and true)' },
  { nombre: 'rotar el celular de un analista de baja', aviso: 'El analista del celular ya no está activo' },
  { nombre: 'puerta abierta a anon', por: 'postflight', espera: 'EXECUTE inesperado',
    buscar: "    execute pg_catalog.format('grant execute on function %s to authenticated', v_f);", poner: "    execute pg_catalog.format('grant execute on function %s to authenticated, anon', v_f);" },
  { nombre: 'núcleo con EXECUTE para authenticated', por: 'postflight', espera: 'EXECUTE inesperado',
    buscar: "    'private.celulares_asignaciones_listar(uuid)'] loop\n    execute pg_catalog.format('revoke all on function %s from public, anon, authenticated, service_role', v_f);",
    poner: "    'private.celulares_asignaciones_listar(uuid)'] loop\n    execute pg_catalog.format('grant execute on function %s to authenticated', v_f);" },
  { nombre: 'puerta INVOKER', por: 'postflight', espera: 'debería ser SECURITY DEFINER',
    buscar: 'create function crm.asociar_llamada_celular(p_evento_id uuid, p_lead_id uuid)\nreturns jsonb\nlanguage plpgsql\nvolatile\nsecurity definer',
    poner: 'create function crm.asociar_llamada_celular(p_evento_id uuid, p_lead_id uuid)\nreturns jsonb\nlanguage plpgsql\nvolatile\nsecurity invoker' },
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
function lineaError(texto) {
  const linea = texto.split('\n').find((l) => /ERROR:/.test(l)) ?? cola(texto, 200);
  return linea.replace(/^.*ERROR:\s*/, '').slice(0, 170);
}

const pasos = [];
function paso(nombre, ok, detalle = '') {
  pasos.push({ nombre, ok: Boolean(ok) });
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${nombre}${detalle ? `\n      ${detalle.replace(/\n/g, '\n      ')}` : ''}`);
  return Boolean(ok);
}

function escaparRegex(texto) {
  return texto.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}
function aplicarCambio(texto, cambio) {
  if (cambio.aviso) {
    const patron = new RegExp(
      `raise exception using errcode = '[0-9A-Z]{5}',(\\s*message = (?:pg_catalog\\.format\\()?'${escaparRegex(cambio.aviso)})`, 'g');
    const total = (texto.match(patron) ?? []).length;
    const esperado = cambio.total ?? 1;
    if (total !== esperado) return { error: `el aviso «${cambio.aviso}» aparece ${total} veces (se esperaban ${esperado})` };
    const objetivo = cambio.ocurrencia ?? 1;
    let n = 0;
    return { texto: texto.replace(patron, (todo, resto) => (++n === objetivo ? `raise notice using${resto}` : todo)) };
  }
  const veces = texto.split(cambio.buscar).length - 1;
  if (veces !== 1) return { error: `el fragmento aparece ${veces} veces` };
  return { texto: texto.replace(cambio.buscar, cambio.poner) };
}
function aplicarMutante(original, mutante) {
  let texto = original;
  for (const cambio of mutante.cambios ?? [mutante]) {
    const r = aplicarCambio(texto, cambio);
    if (r.error) return r;
    texto = r.texto;
  }
  return { texto };
}

function pasadaMutantes(titulo, migracion, mutantes, plantilla, oraculo, marca) {
  console.log(`\n— ${titulo} —`);
  const original = readFileSync(migracion, 'utf8').replace(/\r\n/g, '\n');
  mutantes.forEach((mutante, i) => {
    const etiqueta = `${marca} ${String(i + 1).padStart(2, '0')}: ${mutante.nombre}`;
    const m = aplicarMutante(original, mutante);
    if (m.error) { paso(etiqueta, false, `mutante obsoleto: ${m.error}`); return; }
    const archivo = join(temporal, `${marca}-${i + 1}.sql`);
    writeFileSync(archivo, m.texto);
    const db = `${marca}_${i + 1}`;
    psqlSql(`create database ${db} template ${plantilla}`, 'postgres');
    const aplicado = psqlArchivo(archivo, db);
    if (mutante.por === 'postflight') {
      paso(etiqueta, !aplicado.ok && aplicado.salida.includes(mutante.espera),
        aplicado.ok ? 'SOBREVIVE: la migración mutada se aplicó' : `cazado por el postflight: ${lineaError(aplicado.salida)}`);
    } else if (!aplicado.ok) {
      paso(etiqueta, false, `la migración mutada no se aplica (mutante inválido): ${lineaError(aplicado.salida)}`);
    } else {
      const r = psqlArchivo(oraculo, db);
      paso(etiqueta, !r.ok, r.ok ? 'SOBREVIVE: el oráculo no lo nota' : `cazado por el oráculo: ${lineaError(r.salida)}`);
    }
    psqlSql(`drop database ${db}`, 'postgres');
  });
}

// Una sesión psql en paralelo (para la concurrencia): devuelve su salida y cuánto tardó.
function psqlParalelo(sql, db) {
  return new Promise((resolve) => {
    const archivo = join(temporal, `sesion-${randomBytes(4).toString('hex')}.sql`);
    writeFileSync(archivo, sql);
    const inicio = Date.now();
    const p = spawn(join(PG, `psql${EXE}`), ['-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-d', db, '-f', archivo], { env });
    let salida = '';
    p.stdout.on('data', (d) => { salida += d; });
    p.stderr.on('data', (d) => { salida += d; });
    p.on('close', (code) => resolve({ ok: code === 0, salida: salida.split(clave).join('<clave>'), ms: Date.now() - inicio }));
  });
}
const pausa = (ms) => new Promise((r) => { setTimeout(r, ms); });
const RETIENE_MS = 2000;

async function pasadaConcurrencia() {
  console.log('\n— Pasada 4: concurrencia con dos sesiones reales —');
  const db = 'concurrencia';
  psqlSql(`create database ${db} template plantilla_datos`, 'postgres');
  let r = psqlArchivo(MIG_NUCLEO, db);
  if (!paso('banco de concurrencia listo (datos + núcleo)', r.ok, r.ok ? '' : cola(r.salida))) return;
  const a1 = '00000000-0000-0000-0000-0000000000a1';
  const c1 = '00000000-0000-0000-0000-0000000000c1';
  r = psqlSql(`insert into crm.celulares_asignaciones (etiqueta, analista_id, credencial_hash) values ('C1', '${a1}', repeat('a', 64)) returning id`, db);
  const asig = r.salida.trim();
  const evento = (origen, extra = '') =>
    `'{"v": 1, "evento_origen_id": "${origen}", "numero": "900000001", "direccion": "saliente"${extra}}'::jsonb`;
  const ingerir = (origen, extra) => `select private.llamada_celular_ingerir('${asig}', ${evento(origen, extra)})::text;`;
  const retener = (sql) => `begin;\n${sql}\nselect pg_sleep(${RETIENE_MS / 1000});\ncommit;\n`;

  // Dos envíos del mismo origen con el MISMO contenido: la segunda espera y responde «repetido».
  let [s1, s2] = await Promise.all([
    psqlParalelo(retener(ingerir('conc-1')), db),
    pausa(400).then(() => psqlParalelo(ingerir('conc-1'), db)),
  ]);
  const id1 = /"evento_id": "([0-9a-f-]{36})"/.exec(s1.salida)?.[1];
  paso('mismo origen a la vez, mismo contenido → la segunda espera y devuelve el mismo evento',
    s1.ok && s2.ok && id1 && s2.salida.includes(`"evento_id": "${id1}"`) && s2.salida.includes('"repetido": true') && s2.ms >= RETIENE_MS - 600,
    `segunda sesión: ${s2.ms} ms · ${(s2.salida.trim().split('\n').pop() ?? '').slice(0, 140)}`);

  // Mismo origen con OTRO contenido a la vez: la segunda espera y recibe el conflicto.
  [s1, s2] = await Promise.all([
    psqlParalelo(retener(ingerir('conc-2', ', "duracion_seg": 10')), db),
    pausa(400).then(() => psqlParalelo(ingerir('conc-2', ', "duracion_seg": 20'), db)),
  ]);
  paso('mismo origen a la vez, otro contenido → la segunda espera y recibe el conflicto',
    s1.ok && !s2.ok && s2.salida.includes('llegó a la vez con otro contenido') && s2.ms >= RETIENE_MS - 600,
    `segunda sesión: ${s2.ms} ms · ${lineaError(s2.salida)}`);

  // Dos consumidores enlazan la MISMA llamada con dos resultados distintos: uno gana.
  r = psqlSql(`${ingerir('conc-3')}`, db);
  const ev = /"evento_id": "([0-9a-f-]{36})"/.exec(r.salida)?.[1];
  r = psqlSql(`select set_config('crm.op_resultado_llamada', 'on', false);
    insert into crm.actividades (lead_id, tipo, metadata, creado_por) values
      ('${c1}', 'llamada_realizada', '{"evento": "resultado_llamada", "resultado": "volver_a_llamar"}', '${a1}'),
      ('${c1}', 'llamada_no_contestada', '{"evento": "resultado_llamada", "resultado": "no_contesto"}', '${a1}')
    returning id;`, db);
  // En Windows psql termina las líneas con \r\n.
  const [actX, actY] = r.salida.trim().split(/\r?\n/).filter((l) => /^[0-9a-f-]{36}$/.test(l));
  const como = `set local role authenticated;\nselect set_config('request.jwt.claim.sub', '${a1}', true);\n`;
  const enlazar = (act) => `select crm.enlazar_llamada_celular('${ev}', '${act}')::text;`;
  [s1, s2] = await Promise.all([
    psqlParalelo(retener(`${como}${enlazar(actX)}`), db),
    pausa(400).then(() => psqlParalelo(`begin;\n${como}${enlazar(actY)}\ncommit;\n`, db)),
  ]);
  paso('dos consumidores enlazan la misma llamada → el segundo espera y es rechazado',
    Boolean(ev && actX && actY) && s1.ok && !s2.ok && s2.salida.includes('ya tiene su resultado registrado') && s2.ms >= RETIENE_MS - 600,
    `segunda sesión: ${s2.ms} ms · ${lineaError(s2.salida)}`);
  r = psqlSql(`select count(*) from crm.llamadas_celular_enlaces where evento_id = '${ev}'`, db);
  paso('queda exactamente un enlace', r.ok && r.salida.trim() === '1', r.salida.trim());
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

  // Plantillas: el banco reducido solo, y con los datos (F2-b) para los mutantes del núcleo.
  let r = psqlSql('create database plantilla', 'postgres');
  if (!r.ok) throw new Error(`no se pudo crear la plantilla:\n${cola(r.salida)}`);
  r = psqlArchivo(BASE, 'plantilla');
  paso('banco reducido sembrado', r.ok, r.ok ? '' : cola(r.salida));
  if (!r.ok) throw new Error('sin banco reducido no hay pruebas');
  psqlSql('create database plantilla_datos template plantilla', 'postgres');
  r = psqlArchivo(MIG_DATOS, 'plantilla_datos');
  if (!r.ok) throw new Error(`la plantilla con datos no se pudo preparar:\n${cola(r.salida)}`);
  psqlSql('create database principal template plantilla', 'postgres');

  console.log('\n— Pasada 1: las migraciones tal cual —');
  const db = 'principal';
  const oraculoDatos = (nombre) => {
    const o = psqlArchivo(ORACULO_DATOS, db);
    return paso(nombre, o.ok && o.salida.includes('ORACULO F2-b OK'), lineasOraculo(o.salida));
  };
  const oraculoNucleo = (nombre) => {
    const o = psqlArchivo(ORACULO_NUCLEO, db);
    return paso(nombre, o.ok && o.salida.includes('ORACULO F2-c OK'), lineasOraculo(o.salida));
  };
  r = psqlArchivo(MIG_DATOS, db);
  paso('F2-b aplicada (precondición, tablas, candados, purga, postflight)', r.ok, r.ok ? '' : cola(r.salida));
  r = psqlArchivo(MIG_DATOS, db);
  paso('F2-b se niega a sobrescribirse', !r.ok && r.salida.includes('los objetos ya existen'), r.ok ? 'se aplicó dos veces' : '');
  oraculoDatos('oráculo de F2-b');
  r = psqlArchivo(MIG_NUCLEO, db);
  paso('F2-c aplicada (núcleo, puertas, permisos, postflight)', r.ok, r.ok ? '' : cola(r.salida));
  r = psqlArchivo(MIG_NUCLEO, db);
  paso('F2-c se niega a sobrescribirse', !r.ok && r.salida.includes('los objetos ya existen'), r.ok ? 'se aplicó dos veces' : '');
  oraculoNucleo('oráculo de F2-c');
  oraculoDatos('oráculo de F2-b con F2-c instalado');
  r = psqlSql('select count(*) from crm.llamadas_celular_eventos', db);
  paso('los oráculos no dejaron filas (terminan en ROLLBACK)', r.ok && r.salida.trim() === '0', r.salida.trim());

  r = psqlArchivo(REVERSA_DATOS, db);
  paso('la reversa de datos se niega con el núcleo instalado', !r.ok && r.salida.includes('el núcleo F2-c sigue instalado'), r.ok ? 'se aplicó fuera de orden' : '');
  r = psqlArchivo(REVERSA_NUCLEO, db);
  paso('reversa del núcleo', r.ok, r.ok ? '' : cola(r.salida));
  r = psqlSql('select count(*) from crm.llamadas_celular_politica', db);
  paso('tras esa reversa las tablas siguen', r.ok && r.salida.trim() === '1', r.salida.trim());
  r = psqlArchivo(MIG_NUCLEO, db);
  paso('F2-c se vuelve a aplicar tras su reversa', r.ok, r.ok ? '' : cola(r.salida));
  oraculoNucleo('oráculo de F2-c tras reaplicar');
  r = psqlArchivo(REVERSA_NUCLEO, db);
  paso('reversa del núcleo (otra vez, antes de los datos)', r.ok, r.ok ? '' : cola(r.salida));

  r = psqlArchivo(REVERSA_DATOS, db);
  paso('reversa de datos que conserva los hechos', r.ok, r.ok ? '' : cola(r.salida));
  r = psqlSql('select count(*) from crm.llamadas_celular_politica', db);
  paso('tras esa reversa las tablas siguen (política con 1 fila)', r.ok && r.salida.trim() === '1', r.salida.trim());
  r = psqlSql("insert into crm.celulares_asignaciones (etiqueta, analista_id, credencial_hash) "
    + "select 'C9', e.perfil_id, repeat('e', 64) from crm.equipo e where e.rol_crm = 'vendedor' and e.activo order by e.perfil_id limit 1", db);
  paso('fila de prueba para la reversa total', r.ok, r.ok ? '' : cola(r.salida));
  r = psqlArchivo(REVERSA_TOTAL, db);
  paso('reversa total se niega si hay filas', !r.ok && r.salida.includes('la evidencia no se borra'), r.ok ? 'borró con filas' : '');
  r = psqlSql("delete from crm.celulares_asignaciones where etiqueta = 'C9'", db);
  paso('fila de prueba retirada', r.ok, r.ok ? '' : cola(r.salida));
  r = psqlArchivo(REVERSA_TOTAL, db);
  paso('reversa total sin filas', r.ok, r.ok ? '' : cola(r.salida));
  r = psqlArchivo(MIG_DATOS, db);
  paso('F2-b se vuelve a aplicar tras la reversa total', r.ok, r.ok ? '' : cola(r.salida));
  r = psqlArchivo(MIG_NUCLEO, db);
  paso('F2-c se vuelve a aplicar encima', r.ok, r.ok ? '' : cola(r.salida));
  oraculoDatos('oráculo de F2-b tras reaplicar todo');
  oraculoNucleo('oráculo de F2-c tras reaplicar todo');

  pasadaMutantes('Pasada 2: mutantes de F2-b (datos)', MIG_DATOS, MUTANTES_DATOS, 'plantilla', ORACULO_DATOS, 'mut_datos');
  pasadaMutantes('Pasada 3: mutantes de F2-c (núcleo y puertas)', MIG_NUCLEO, MUTANTES_NUCLEO, 'plantilla_datos', ORACULO_NUCLEO, 'mut_nucleo');
  await pasadaConcurrencia();
} catch (error) {
  paso('arranque del banco', false, error.message);
} finally {
  if (arrancado) correr('pg_ctl', ['-D', datos, '-m', 'fast', '-w', 'stop'], { sinTuberias: true });
  try { rmSync(temporal, { recursive: true, force: true }); } catch { /* carpeta temporal */ }
}

const fallos = pasos.filter((p) => !p.ok).length;
console.log(fallos ? `\n${fallos} de ${pasos.length} pasos FALLARON` : `\nTODO EN VERDE: ${pasos.length} pasos`);
process.exit(fallos ? 1 : 0);
