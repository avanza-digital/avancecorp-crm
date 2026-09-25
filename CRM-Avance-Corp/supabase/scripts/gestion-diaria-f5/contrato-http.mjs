// Transporte PostgREST real en una copia efímera del banco F5. Sólo localhost.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHmac, randomBytes } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { db, contenedor, socket, sql } from './banco.mjs';

const copia = 'gestion_diaria_f5_http_20260924';
const servicio = 'avancecorp-gd-f5-http';
const puerto = 58442;
const docker = (args, opciones = {}) => {
  const r = spawnSync('docker', ['--host', socket, ...args], {
    encoding: 'utf8', maxBuffer: 16 * 1024 * 1024, ...opciones,
  });
  assert.equal(r.status, 0, `Docker ${args[0]}: ${r.stderr}`);
  return r.stdout.trim();
};
sql('select private.assert_gestion_diaria_pulso();');
assert.ok(!docker(['ps', '-a', '--format', '{{.Names}}']).split('\n').includes(servicio), 'Banco HTTP F5 ocupado; no se detiene otro proceso');
const red = Object.keys(JSON.parse(docker(['inspect', contenedor]))[0].NetworkSettings.Networks)[0];
assert.ok(red);
// Reutiliza la conexión local existente sin mostrarla ni cambiar roles compartidos.
const rest = JSON.parse(docker(['inspect', 'supabase_rest_avancecorp-f5-bank']))[0];
const uri = new URL(rest.Config.Env.find((v) => v.startsWith('PGRST_DB_URI=')).slice('PGRST_DB_URI='.length));
assert.equal(uri.hostname, contenedor);
uri.pathname = `/${copia}`;
const secreto = randomBytes(32).toString('hex');
const tokens = new Map();
const jwt = (id) => {
  if (tokens.has(id)) return tokens.get(id);
  const cabecera = Buffer.from(JSON.stringify({ alg: 'HS256', typ: 'JWT' })).toString('base64url');
  const cuerpo = Buffer.from(JSON.stringify({ sub: id, role: 'authenticated', exp: Math.floor(Date.now() / 1000) + 300 })).toString('base64url');
  const token = `${cabecera}.${cuerpo}.${createHmac('sha256', secreto).update(`${cabecera}.${cuerpo}`).digest('base64url')}`;
  tokens.set(id, token);
  return token;
};
let creada = false;
let levantado = false;
let verificaciones = 0;
try {
  docker(['exec', contenedor, 'createdb', '-U', 'supabase_admin', '-O', 'postgres', '-T', db, copia]);
  creada = true;
  const pg = (texto) => docker(['exec', '-i', contenedor, 'psql', '-X', '-qAt', '-U', 'postgres', '-d', copia, '-v', 'ON_ERROR_STOP=1', '-f', '-'], {
    input: `do $destino$ begin if current_database()<>'${copia}' then raise exception 'Destino HTTP F5 inválido'; end if; end $destino$;\n${texto}`,
  });
  const fixture = readFileSync(new URL('./test-pulso-habitos.sql', import.meta.url), 'utf8').split('create temporary table f5_fotos')[0];
  const lineas = pg(`${fixture}\nselect row_to_json(fila) from f5_actores fila;\ncommit;`).split('\n');
  const actores = JSON.parse(lineas.findLast((l) => l.startsWith('{"a"')));
  for (const [clave, valor] of Object.entries(actores)) {
    assert.match(valor, clave === 'dia' ? /^\d{4}-\d{2}-\d{2}$/ : /^[0-9a-f-]{36}$/);
  }
  docker(['run', '--rm', '-d', '--name', servicio, '--network', red,
    '--label', 'avancecorp.task=gestion-diaria-f5', '-p', `127.0.0.1:${puerto}:3000`,
    '-e', 'PGRST_DB_URI', '-e', 'PGRST_JWT_SECRET', '-e', 'PGRST_DB_SCHEMAS=crm',
    '-e', 'PGRST_DB_ANON_ROLE=anon', '-e', 'PGRST_DB_CONFIG=false',
    'public.ecr.aws/supabase/postgrest:v14.5'], {
    env: { ...process.env, PGRST_DB_URI: uri.toString(), PGRST_JWT_SECRET: secreto },
  });
  levantado = true;
  const base = `http://127.0.0.1:${puerto}`;
  for (let n = 0; n < 40; n++) {
    try {
      const r = await fetch(base, { signal: AbortSignal.timeout(1000) });
      if (r.status === 503) throw new Error('Caché inicial pendiente');
      break;
    } catch {
      if (n === 39) throw new Error('PostgREST F5 no inició');
      await new Promise((r) => setTimeout(r, 250));
    }
  }
  const rpc = async (nombre, actor, args) => {
    const respuesta = await fetch(`${base}/rpc/${nombre}`, { method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Content-Profile': 'crm', ...(actor ? { Authorization: `Bearer ${jwt(actor)}` } : {}) },
      body: JSON.stringify(args), signal: AbortSignal.timeout(15000),
    });
    verificaciones++;
    return { status: respuesta.status, body: await respuesta.json() };
  };
  const puertas = [
    ['gestion_diaria_pulso_fn', { p_dia: actores.dia }],
    ['gestion_diaria_habitos_fn', { p_hasta: actores.dia, p_dias: 7 }],
  ];
  for (const actor of [actores.gerente, actores.lector_global]) {
    const pulso = await rpc(puertas[0][0], actor, puertas[0][1]);
    assert.equal(pulso.status, 200, JSON.stringify(pulso.body));
    assert.equal(pulso.body.actual.llamadas, 9);
    assert.equal(pulso.body.actual.utiles, 8);
    assert.equal(pulso.body.actual.contestadas, 5);
    assert.equal(pulso.body.actual.leads_unicos, 2);
    assert.equal(pulso.body.vencidas_global, 1008);
    assert.equal(pulso.body.equipos.reduce((s, e) => s + e.metricas.llamadas, 0), 9);
    assert.equal(pulso.body.referencia.media.llamadas, 4);
    const habitos = await rpc(puertas[1][0], actor, puertas[1][1]);
    assert.equal(habitos.status, 200, JSON.stringify(habitos.body));
    assert.equal(habitos.body.umbral_tasa_baja, null);
    assert.equal(habitos.body.dias_incluidos, 7);
    const dia = habitos.body.personas.find((p) => p.analista_id === actores.a).dias.find((d) => d.dia === actores.dia);
    assert.equal(dia.jornada.hueco.minutos, 165);
  }
  for (const actor of [actores.a, actores.supervisor_a, actores.coordinador, actores.revocado]) {
    for (const [nombre, args] of puertas) {
      const r = await rpc(nombre, actor, args);
      assert.equal(r.status, 403); assert.equal(r.body.code, '42501');
    }
  }
  const detalleGlobal = await rpc('gestion_diaria_equipo_fn', actores.gerente, { p_dia: actores.dia });
  assert.equal(detalleGlobal.status, 200, JSON.stringify(detalleGlobal.body));
  assert.equal(detalleGlobal.body.supervisor_id, null);
  const incluidos = new Set(detalleGlobal.body.equipo.map((p) => p.analista_id));
  for (const id of [actores.a, actores.b, actores.c]) assert.ok(incluidos.has(id), 'Detalle global incompleto');
  // NULL conserva el ámbito propio de F4 para supervisión; no concede el global.
  const propio = await rpc('gestion_diaria_equipo_fn', actores.supervisor_b, { p_dia: actores.dia });
  assert.equal(propio.status, 200, JSON.stringify(propio.body));
  assert.equal(propio.body.supervisor_id, actores.supervisor_b);
  assert.ok(propio.body.equipo.some((p) => p.analista_id === actores.b));
  assert.ok(!propio.body.equipo.some((p) => [actores.a, actores.c].includes(p.analista_id)));
  const ajeno = await rpc('gestion_diaria_equipo_fn', actores.supervisor_b, { p_dia: actores.dia, p_supervisor_id: actores.supervisor_a });
  assert.equal(ajeno.status, 403); assert.equal(ajeno.body.code, '42501');
  for (const [nombre, args] of puertas) {
    const anon = await rpc(nombre, null, args);
    assert.ok([401, 403, 404].includes(anon.status));
  }
  const invalido = await rpc('gestion_diaria_habitos_fn', actores.gerente, { p_dias: 31 });
  assert.equal(invalido.status, 400); assert.equal(invalido.body.code, '22023');
  const infinito = await rpc('gestion_diaria_pulso_fn', actores.gerente, { p_dia: 'infinity' });
  assert.equal(infinito.status, 400); assert.equal(infinito.body.code, '22023');
  const tokenAnterior = jwt(actores.gerente);
  pg(`begin; alter table crm.equipo disable trigger user; update crm.equipo set activo=false where perfil_id='${actores.gerente}'; alter table crm.equipo enable trigger user; commit;`);
  for (const [nombre, args] of puertas) {
    const r = await rpc(nombre, actores.gerente, args);
    assert.equal(r.status, 403); assert.equal(r.body.code, '42501');
  }
  assert.equal(jwt(actores.gerente), tokenAnterior);
  console.log(`PASS HTTP PostgREST 14.5: ${verificaciones} solicitudes reales, dos lectores autorizados, cuatro roles denegados, anon, fechas/entrada inválidas y revocación con el mismo JWT.`);
} finally {
  if (levantado) docker(['stop', servicio]);
  if (creada) docker(['exec', contenedor, 'dropdb', '-U', 'supabase_admin', copia]);
}
