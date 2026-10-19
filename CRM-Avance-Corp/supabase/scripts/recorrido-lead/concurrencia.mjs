// Conexiones reales y esperas observadas en pg_stat_activity. Solo stack propio.
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { spawn } from 'node:child_process';
import { setTimeout as esperar } from 'node:timers/promises';
import { contenedor, literal as q, sql } from './banco.mjs';

const gerente = 'bf1c562e-ed08-4cc3-92a8-34f1fa3e9127';
const analista = 'b0000000-0000-4000-8000-000000000002';
// application_name se trunca a 63 bytes en PostgreSQL; reservar espacio para
// el escenario permite observar y limpiar exactamente las sesiones creadas.
const prefijo = `prueba_recorrido_${randomUUID().replaceAll('-', '').slice(0, 16)}`;
const sesiones = [];
const lead = randomUUID();
const leadCita = randomUUID();
const tarea = randomUUID();
let actividad;

function sesion(nombre) {
  const app = `${prefijo}_${nombre}`;
  const p = spawn('docker', ['exec', '-i', contenedor, 'psql', '-X', '-qAt', '-U', 'supabase_admin',
    '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-f', '-']);
  const s = { p, app, salida: '', error: '', codigo: null };
  p.stdout.on('data', (d) => { s.salida += d; });
  p.stderr.on('data', (d) => { s.error += d; });
  p.stdin.on('error', () => {}); // La salida del proceso conserva el error SQL.
  s.fin = new Promise((resolve) => p.on('close', (codigo) => { s.codigo = codigo; resolve(codigo); }));
  s.enviar = (texto) => p.stdin.write(texto + '\n');
  s.cerrar = async (texto = '') => { p.stdin.end(texto + '\n'); await s.fin; return s; };
  s.enviar(`\\set VERBOSITY verbose\nset application_name=${q(app)}; set role postgres; set statement_timeout='15s';`);
  sesiones.push(s);
  return s;
}
async function hasta(predicado, mensaje) {
  const fin = Date.now() + 7000;
  while (Date.now() < fin) {
    if (await predicado()) return;
    await esperar(25);
  }
  assert.fail(mensaje);
}
const marcador = (s, texto) => hasta(() => {
  assert.ok(s.codigo === null, s.error || 'La sesión terminó antes del marcador');
  return s.salida.includes(texto);
}, `No llegó ${texto}`);
const esperaLock = (s) => hasta(() => sql(`select exists(select 1 from pg_stat_activity
  where application_name=${q(s.app)} and wait_event_type='Lock');`) === 't', 'No se observó la espera de lock');
const correcto = (s) => assert.equal(s.codigo, 0, s.error);
const insertar = (id, tipo, extra = '') => `insert into crm.actividades(lead_id,tipo,detalle${extra ? ',metadata' : ''})
  values(${q(id)},${q(tipo)},'Concurrencia sintetica'${extra ? ',' + q(extra) + '::jsonb' : ''});`;

try {
  const telefono = 980000000 + Math.floor(Math.random() * 8000000);
  sql(`begin; insert into crm.leads(id,nombre_completo,telefono,origen,vendedor_id,monto_estimado,moneda,creado_por) values
    (${q(lead)},'BANCO CONCURRENCIA RECORRIDO',${q(telefono)},'landing',${q(analista)},1000,'PEN',${q(analista)}),
    (${q(leadCita)},'BANCO CONCURRENCIA CITA',${q(telefono + 1)},'landing',${q(analista)},1000,'PEN',${q(analista)});
    insert into crm.tareas(id,lead_id,tipo,titulo,vence_en,modalidad_reunion,ubicacion_reunion,creado_por)
      values(${q(tarea)},${q(leadCita)},'reunion','Cita concurrente',clock_timestamp()-interval '1 minute','presencial','Oficina',${q(analista)});
    set local request.jwt.claim.sub=${q(analista)};
    select crm.cerrar_reunion_v3(${q(randomUUID())},${q(tarea)},'completada','interesado',null,'Entrevista',null,1000,'PEN'); commit;`);
  actividad = sql(`select resultado_actividad_id from crm.tareas where id=${q(tarea)};`);

  // Dos inserts internos: el segundo espera ANTES del FK; ambos terminan.
  const a = sesion('insert_a');
  a.enviar(`begin; ${insertar(lead, 'llamada_no_contestada')}\n\\echo PRIMERO_LISTO`);
  await marcador(a, 'PRIMERO_LISTO');
  const b = sesion('insert_b');
  b.enviar(`begin; ${insertar(lead, 'whatsapp_enviado')}\n\\echo SEGUNDO_LISTO`);
  await esperaLock(b);
  correcto(await a.cerrar('commit;'));
  await marcador(b, 'SEGUNDO_LISTO');
  correcto(await b.cerrar('commit;'));
  assert.equal(sql(`select count(*) from crm.actividad_ciclo_contexto where lead_id=${q(lead)} and ciclo_n=1;`), '2');
  console.log('PASS: inserts internos concurrentes serializados, sin deadlock ni contexto perdido.');

  // Reabrir y registrar al mismo tiempo: la actividad recibe el ciclo nuevo.
  const c = sesion('ciclo_a');
  c.enviar(`begin; set local request.jwt.claim.sub=${q(gerente)};
    update crm.leads set etapa='descartado',motivo_descarte='sin_interes' where id=${q(lead)};
    select crm.reabrir_lead_fn(${q(lead)});\n\\echo CICLO_LISTO`);
  await marcador(c, 'CICLO_LISTO');
  const d = sesion('ciclo_b');
  d.enviar(`begin; ${insertar(lead, 'llamada_no_contestada')}\n\\echo ACTIVIDAD_LISTA`);
  await esperaLock(d);
  correcto(await c.cerrar('commit;'));
  await marcador(d, 'ACTIVIDAD_LISTA');
  correcto(await d.cerrar('commit;'));
  assert.equal(sql(`select count(*) from crm.actividad_ciclo_contexto where lead_id=${q(lead)} and ciclo_n=2;`), '1');
  console.log('PASS: reapertura concurrente captura el ciclo confirmado después de esperar.');

  // Writer inverso fila→lead no se queda esperando: aborta con 55P03.
  const e = sesion('invalida_a');
  e.enviar(`begin; select id from crm.leads where id=${q(leadCita)} for update;\n\\echo LEAD_BLOQUEADO`);
  await marcador(e, 'LEAD_BLOQUEADO');
  const f = sesion('invalida_b');
  await f.cerrar(`begin; update crm.actividades set metadata=metadata||jsonb_build_object('deshecho_en',clock_timestamp()) where id=${q(actividad)}; commit;`);
  assert.notEqual(f.codigo, 0);
  assert.match(f.error, /55P03/);
  correcto(await e.cerrar('commit;'));
  assert.equal(sql(`select metadata ? 'deshecho_en' from crm.actividades where id=${q(actividad)};`), 'f');
  console.log('PASS: invalidación en orden inverso rechaza sin efectos ni espera circular.');

  // Lectura fresca después de esperar al writer que invalida la entrevista.
  const g = sesion('snapshot_a');
  g.enviar(`begin; update crm.actividades set metadata=metadata||jsonb_build_object('deshecho_en',clock_timestamp()) where id=${q(actividad)};\n\\echo DESHECHO_SIN_COMMIT`);
  await marcador(g, 'DESHECHO_SIN_COMMIT');
  const h = sesion('snapshot_b');
  h.enviar(`begin; select id from crm.leads where id=${q(leadCita)} for update;
    select 'ELEGIBLE='||(resultado->>'habilita_conversion') from private.recorrido_evaluar(array[${q(leadCita)}::uuid]);\n\\echo SNAPSHOT_LISTO`);
  await esperaLock(h);
  correcto(await g.cerrar('commit;'));
  await marcador(h, 'SNAPSHOT_LISTO');
  correcto(await h.cerrar('commit;'));
  assert.match(h.salida, /ELEGIBLE=false/);
  console.log('PASS: la evaluación posterior al lock ve la invalidación ya confirmada.');

  if (process.argv.includes('--oficina')) {
    const operar = (id, operacion) => `set local role authenticated;
      set local request.jwt.claim.sub=${q(analista)};
      select crm.recorrido_atender_oficina_fn(${q(operacion)},${q(id)},'interesado','Visita concurrente',null,1100,'PEN');`;
    const leerResultado = (s) => JSON.parse(s.salida.split('\n').find((linea) => linea.startsWith('{')));
    const opDoble = randomUUID();
    const i = sesion('oficina_a');
    i.enviar(`begin; ${operar(lead, opDoble)}\n\\echo VISITA_LISTA`);
    await marcador(i, 'VISITA_LISTA');
    const j = sesion('oficina_b');
    j.enviar(`begin; ${operar(lead, opDoble)}\n\\echo REPLAY_LISTO`);
    await esperaLock(j);
    correcto(await i.cerrar('commit;'));
    await marcador(j, 'REPLAY_LISTO');
    correcto(await j.cerrar('commit;'));
    assert.deepEqual(leerResultado(i), leerResultado(j));
    assert.equal(sql(`select count(*) from crm.actividad_ciclo_contexto where gesto_oficina_id=${q(opDoble)};`), '1');
    console.log('PASS: doble envio simultaneo de oficina devuelve el mismo cierre y una sola asistencia.');

    const opAbortada = randomUUID();
    const k = sesion('oficina_rollback');
    k.enviar(`begin; ${operar(leadCita, opAbortada)}\n\\echo VISITA_SIN_COMMIT`);
    await marcador(k, 'VISITA_SIN_COMMIT');
    const m = sesion('oficina_recuperada');
    m.enviar(`begin; ${operar(leadCita, opAbortada)}\n\\echo VISITA_RECUPERADA`);
    await esperaLock(m);
    correcto(await k.cerrar('rollback;'));
    await marcador(m, 'VISITA_RECUPERADA');
    correcto(await m.cerrar('commit;'));
    assert.equal(sql(`select count(*) from crm.actividad_ciclo_contexto where gesto_oficina_id=${q(opAbortada)};`), '1');
    assert.equal(sql(`select count(*) from crm.multiempresa_idempotencia
      where clave=${q(`recorrido_oficina:${analista}:${opAbortada}`)} and resultado is not null;`), '1');
    console.log('PASS: rollback de una visita concurrente permite reintentar sin recibo ni cita a medias.');
  }
} finally {
  // Solo procesos del ensayo actual. Un error no deja transacciones retenidas.
  for (const s of sesiones) {
    if (s.codigo === null) {
      sql(`select pg_terminate_backend(pid) from pg_stat_activity where application_name=${q(s.app)};`);
      await s.cerrar();
    }
  }
  sql(`begin; set local request.jwt.claim.sub=${q(gerente)};
    do $$ declare v uuid; begin for v in select id from crm.leads where id in (${q(lead)},${q(leadCita)}) loop
      perform crm.eliminar_lead_error_carga(v,'Limpiar fixture sintetico del ensayo concurrente'); end loop; end $$; commit;`);
}
