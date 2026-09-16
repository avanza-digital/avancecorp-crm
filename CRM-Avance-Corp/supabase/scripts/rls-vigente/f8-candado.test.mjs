// Banco SQL propio, vacío y desechable; nunca ejecutar contra producción.
import assert from 'node:assert/strict';
import { execFileSync, spawn } from 'node:child_process';
import { before, beforeEach, test } from 'node:test';
import { setTimeout as delay } from 'node:timers/promises';

const url = process.env.CRM_BANCO_PSQL_URL;
assert(url, 'Falta CRM_BANCO_PSQL_URL del banco de concurrencia');
const destino = new URL(url);
assert(['127.0.0.1', 'localhost', '::1'].includes(destino.hostname));
assert.match(destino.pathname, /^\/rls_f8_locks_[a-z0-9_]+$/);
const args = ['-XqAt', '-v', 'ON_ERROR_STOP=1', '--set', 'VERBOSITY=verbose'];
const env = {
  ...process.env,
  PGHOST: destino.hostname,
  PGPORT: destino.port || '5432',
  PGDATABASE: destino.pathname.slice(1),
  PGUSER: decodeURIComponent(destino.username),
  PGPASSWORD: decodeURIComponent(destino.password),
};
const gerencia = 'f8000000-0000-4000-8000-000000000001';
const supervisor = 'f8000000-0000-4000-8000-000000000002';
const vendedor1 = 'f8000000-0000-4000-8000-000000000003';
const vendedor2 = 'f8000000-0000-4000-8000-000000000004';
const activar = `update crm.piloto_f8_control set activo=true,
  inicia_en=statement_timestamp()-interval '1 minute',
  vence_en=statement_timestamp()+interval '15 minutes',
  actualizado_por='${gerencia}', motivo='Ensayo sintético de concurrencia F8' where singleton;`;

function sql(texto) {
  try {
    return execFileSync('psql', args, { env, input: texto, encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] }).trim();
  } catch (error) {
    throw new Error(String(error.stderr ?? 'Error SQL en banco local'));
  }
}

function conexion(nombre) {
  const child = spawn('psql', args, { env, stdio: ['pipe', 'pipe', 'pipe'] });
  let salida = '';
  let errores = '';
  let terminado = false;
  child.stdout.on('data', (dato) => { salida += dato; });
  child.stderr.on('data', (dato) => { errores += dato; });
  const fin = new Promise((resolve, reject) => {
    child.once('error', reject);
    child.once('close', (code) => { terminado = true; resolve({ code, salida, errores }); });
  });
  child.stdin.write(`set application_name='${nombre}'; set lock_timeout='4s';\n`);
  return {
    enviar: (texto) => child.stdin.write(texto + '\n'),
    terminar: (texto = 'rollback;') => { if (!terminado) child.stdin.end(texto + '\n\\q\n'); return fin; },
    terminado: () => terminado,
    salida: () => salida,
    fin,
  };
}

async function esperar(condicion, limite = 2500) {
  const inicio = Date.now();
  do {
    if (condicion()) return true;
    await delay(25);
  } while (Date.now() - inicio < limite);
  return false;
}

async function retenida(nombre, cambio) {
  const c = conexion(nombre);
  c.enviar(`begin; ${cambio} select 'RETENIDA';`);
  const lista = await esperar(() => c.salida().includes('RETENIDA') || c.terminado());
  if (!lista || c.terminado()) {
    const resultado = await c.terminar();
    assert.fail('No se pudo retener la transacción: ' + resultado.errores);
  }
  return c;
}

async function esperaAdvisory(nombre, conexion, llave) {
  const esperando = () => sql(`select exists(select 1 from pg_locks l join pg_stat_activity a on a.pid=l.pid
    where a.datname=current_database() and a.application_name='${nombre}'
      and l.locktype='advisory' and not l.granted and l.objsubid=1
      and l.objid=(hashtext('${llave}')::bigint & 4294967295)::oid
      and l.classid=(case when hashtext('${llave}')<0 then 4294967295 else 0 end)::oid)::int`) === '1';
  let observado = false;
  await esperar(() => { observado = esperando(); return observado || conexion.terminado(); });
  return observado;
}

before(() => {
  assert.equal(sql('select current_database()'), destino.pathname.slice(1));
  assert.equal(sql('select count(*) from public.perfiles'), '0', 'Exige banco vacío propio');
  sql(`begin;
    insert into auth.users(id) values ('${gerencia}'),('${supervisor}'),('${vendedor1}'),('${vendedor2}');
    insert into public.perfiles(id,nombre_completo,rol,activo) values
      ('${gerencia}','F8 GERENCIA FICTICIA','comercial',true),
      ('${supervisor}','F8 SUPERVISOR FICTICIO','comercial',true),
      ('${vendedor1}','F8 ANALISTA UNO FICTICIO','comercial',true),
      ('${vendedor2}','F8 ANALISTA DOS FICTICIO','comercial',true);
    insert into crm.equipo(perfil_id,rol_crm,supervisor_id,activo) values
      ('${gerencia}','gerencia',null,true),('${supervisor}','supervisor',null,true),
      ('${vendedor1}','vendedor','${supervisor}',true),('${vendedor2}','vendedor','${supervisor}',true);
    insert into crm.multiempresa_flags(nombre,activo) values
      ('resolver_en_puertas',true),('inversiones_escritura',false),('ficha_360_neutral',false),
      ('postventa_neutral',false),('metricas_multiempresa_sombra',false);
    insert into crm.piloto_f8_control(singleton,activo) values(true,false);
    insert into crm.piloto_f8_miembros(perfil_id,rol_esperado,habilitado_desde,vence_en,motivo,actualizado_por)
      select perfil_id,rol_crm,statement_timestamp()-interval '5 minutes',
        statement_timestamp()+interval '10 minutes','Equipo ficticio de ensayo','${gerencia}'
      from crm.equipo;
    commit;`);
});

beforeEach(() => {
  sql(`begin; update crm.piloto_f8_control set activo=false where singleton;
    update crm.multiempresa_flags set activo=(nombre='resolver_en_puertas'); commit;`);
});

test('activación válida incrementa una revisión y conserva F3/F4', () => {
  const antes = Number(sql('select revision from crm.piloto_f8_control'));
  sql(activar);
  assert.equal(sql('select activo::int from crm.piloto_f8_control'), '1');
  assert.equal(Number(sql('select revision from crm.piloto_f8_control')), antes + 1);
  assert.equal(sql("select activo::int from crm.multiempresa_flags where nombre='resolver_en_puertas'"), '1');
  assert.equal(sql("select activo::int from crm.multiempresa_flags where nombre='inversiones_escritura'"), '0');
});

test('activación rechaza un apagado F3 en curso sin esperar ni dejar cambios', async () => {
  const revision = sql('select revision from crm.piloto_f8_control');
  const a = await retenida('rls_f8_apagando_f3', "update crm.multiempresa_flags set activo=false where nombre='resolver_en_puertas';");
  const b = conexion('rls_f8_activando');
  try {
    const r = await b.terminar(activar);
    assert.notEqual(r.code, 0);
    assert.match(r.errores, /P0409/);
    assert.match(r.errores, /F3 está cambiando/);
    assert.equal(sql('select revision from crm.piloto_f8_control'), revision);
    assert.equal(sql('select activo::int from crm.piloto_f8_control'), '0');
    assert.equal((await a.terminar('commit;')).code, 0);
    assert.equal(sql("select activo::int from crm.multiempresa_flags where nombre='resolver_en_puertas'"), '0');
  } finally {
    await a.terminar();
    await b.terminar();
  }
});

test('F3 sigue siendo apagado general: espera la activación y cierra F4/F5/F6', async () => {
  const a = await retenida('rls_f8_activacion_retenida', activar);
  const b = conexion('rls_f8_apagado_posterior');
  b.terminar("update crm.multiempresa_flags set activo=false where nombre='resolver_en_puertas';");
  try {
    assert.equal(await esperaAdvisory('rls_f8_apagado_posterior', b, 'crm_flag_resolver_en_puertas'), true);
    assert.equal((await a.terminar('commit;')).code, 0);
    assert.equal((await b.fin).code, 0);
    assert.equal(sql('select activo::int from crm.piloto_f8_control'), '1');
    assert.equal(sql(`begin;
      select set_config('request.jwt.claims','{"sub":"${gerencia}","role":"authenticated"}',true);
      select jsonb_build_array(private.inversiones_escritura_bajo_candado(),
        (crm.cartera_inversionistas_estado_fn()->>'habilitada')::boolean,private.postventa_modo());
      rollback;`).split('\n').at(-1), '[false, false, false]');
  } finally {
    await a.terminar();
    await b.fin;
  }
});

test('apagar F8 sigue permitido bajo REPEATABLE READ y F3 apagado', () => {
  sql(activar);
  sql("update crm.multiempresa_flags set activo=false where nombre='resolver_en_puertas';");
  sql('begin isolation level repeatable read; update crm.piloto_f8_control set activo=false where singleton; commit;');
  assert.equal(sql('select activo::int from crm.piloto_f8_control'), '0');
});

test('activación F8 rechaza el encendido global F4 en curso sin interbloqueo', async () => {
  const a = await retenida('rls_f8_f4_retenido', "update crm.multiempresa_flags set activo=true where nombre='inversiones_escritura';");
  const b = conexion('rls_f8_tras_f4');
  try {
    const r = await b.terminar(activar);
    assert.notEqual(r.code, 0);
    assert.match(r.errores, /P0409/);
    assert.match(r.errores, /control F8 está ocupado/);
    assert.equal((await a.terminar('commit;')).code, 0);
    assert.equal(sql('select activo::int from crm.piloto_f8_control'), '0');
  } finally {
    await a.terminar();
    await b.terminar();
  }
});

test('F4 ON seguido de F3 OFF en la misma transacción no se cruza con la activación', async () => {
  const revision = sql('select revision from crm.piloto_f8_control');
  const a = await retenida('rls_f8_rollout_mixto', "update crm.multiempresa_flags set activo=true where nombre='inversiones_escritura';");
  const b = conexion('rls_f8_activacion_mixta');
  try {
    const r = await b.terminar(activar);
    assert.notEqual(r.code, 0);
    assert.match(r.errores, /P0409/);
    assert.doesNotMatch(r.errores, /40P01|55P03/);
    const cierre = await a.terminar("update crm.multiempresa_flags set activo=false where nombre='resolver_en_puertas'; commit;");
    assert.equal(cierre.code, 0, cierre.errores);
    assert.equal(sql('select revision from crm.piloto_f8_control'), revision);
    assert.equal(sql("select string_agg(nombre||'='||activo::text,',' order by nombre) from crm.multiempresa_flags where nombre in ('resolver_en_puertas','inversiones_escritura')"),
      'inversiones_escritura=true,resolver_en_puertas=false');
  } finally {
    await a.terminar();
    await b.terminar();
  }
});

test('F3 OFF seguido de F8 OFF conserva el apagado sin interbloqueo de fila', async () => {
  const a = await retenida('rls_f8_apagado_mixto', "update crm.multiempresa_flags set activo=false where nombre='resolver_en_puertas';");
  const b = conexion('rls_f8_activacion_con_fila');
  try {
    const r = await b.terminar(activar);
    assert.notEqual(r.code, 0);
    assert.match(r.errores, /P0409/);
    assert.doesNotMatch(r.errores, /40P01|55P03/);
    const cierre = await a.terminar('update crm.piloto_f8_control set activo=false where singleton; commit;');
    assert.equal(cierre.code, 0, cierre.errores);
    assert.equal(sql('select activo::int from crm.piloto_f8_control'), '0');
    assert.equal(sql("select activo::int from crm.multiempresa_flags where nombre='resolver_en_puertas'"), '0');
  } finally {
    await a.terminar();
    await b.terminar();
  }
});

test('el control no se elimina y el trigger conserva eventos y estado', () => {
  assert.throws(() => sql('delete from crm.piloto_f8_control'), /55000.*El control F8 es permanente/);
  assert.equal(sql('select count(*) from crm.piloto_f8_control'), '1');
  assert.equal(sql("select count(*) from pg_trigger where tgrelid='crm.piloto_f8_control'::regclass and tgname='trg_piloto_f8_control_00_validar' and tgtype=27 and tgenabled='O' and tgfoid='private.trg_piloto_f8_control_validar()'::regprocedure"), '1');
});
