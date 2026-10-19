// Base desechable dentro del stack propio: copia solo sus fixtures sintéticos.
// Nunca cambia modo/corte del banco principal ni admite destinos remotos.
import assert from 'node:assert/strict';
import { randomUUID, randomInt } from 'node:crypto';
import { spawn, spawnSync } from 'node:child_process';
import { setTimeout as esperar } from 'node:timers/promises';
import { contenedor, literal as q, sql as banco, archivo } from './banco.mjs';

const db = `recorrido_carrera_${randomUUID().replaceAll('-', '').slice(0, 12)}`;
const gerente = 'bf1c562e-ed08-4cc3-92a8-34f1fa3e9127';
const analista = 'b0000000-0000-4000-8000-000000000002';
const args = ['exec', '-i', contenedor, 'psql', '-X', '-qAt', '-U', 'supabase_admin', '-d', db, '-v', 'ON_ERROR_STOP=1', '-f', '-'];
const cabecera = "\\set VERBOSITY verbose\nset statement_timeout='20s';\n";
const sesiones = [];
const tx = (s, actor = analista) => `begin; set local role authenticated; set local request.jwt.claim.sub=${q(actor)}; ${s} commit;`;
const ejecutar = (s) => spawnSync('docker', args, { input: cabecera + s, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
function sql(s) {
  const r = ejecutar(s); assert.equal(r.status, 0, r.stderr || r.error?.message); return r.stdout.trim();
}
function sesion(nombre) {
  const app = `${db}_${nombre}`, p = spawn('docker', args);
  const s = { app, p, salida: '', error: '', codigo: null };
  p.stdout.on('data', d => { s.salida += d; }); p.stderr.on('data', d => { s.error += d; });
  p.stdin.on('error', () => {});
  s.fin = new Promise(resolve => p.on('close', code => { s.codigo = code; resolve(code); }));
  s.enviar = texto => p.stdin.write(texto + '\n');
  s.cerrar = async (texto = '') => { p.stdin.end(texto + '\n'); await s.fin; return s; };
  s.enviar(cabecera + `set application_name=${q(app)};`); sesiones.push(s); return s;
}
async function hasta(predicado, mensaje) {
  const limite = Date.now() + 8000;
  while (Date.now() < limite) { if (predicado()) return; await esperar(25); }
  assert.fail(mensaje);
}
const marcador = s => hasta(() => {
  assert.equal(s.codigo, null, s.error); return s.salida.includes('LISTO');
}, 'No llegó la barrera SQL');
const esperaLock = s => hasta(() => sql(`select exists(select 1 from pg_stat_activity where datname=${q(db)}
  and application_name=${q(s.app)} and wait_event_type='Lock')`) === 't', 'No se observó una espera real');
const correcto = s => assert.equal(s.codigo, 0, s.error);
const respuesta = s => JSON.parse(s.salida.split('\n').find(l => l.startsWith('{')));
const inicio = `begin; set local role authenticated; set local request.jwt.claim.sub=${q(analista)};`;
const confirmar = f => `select crm.confirmar_inversion_revisada_fn(${q(f.solicitud)},0);`;
const invalidar = f => `update crm.actividades set metadata=metadata||jsonb_build_object('deshecho_en',clock_timestamp()) where id=${q(f.actividad)};`;
function modo(nuevo) {
  const revision = Number(sql('select revision from crm.recorrido_control where id'));
  return tx(`select crm.recorrido_configurar_fn(${q(nuevo)},'Ensayo concurrente en base desechable',${revision});`, gerente);
}
function fixture(nombre) {
  const f = { lead: randomUUID(), solicitud: randomUUID(), documento: String(randomInt(97000000, 97999999)) };
  sql(`insert into crm.leads(id,nombre_completo,telefono,origen,monto_estimado,vendedor_id,creado_por)
    values(${q(f.lead)},${q('BANCO CARRERA ' + nombre)},${q(String(randomInt(970000000, 979999999)))},'oficina',1000,${q(analista)},${q(analista)});`);
  const oficina = JSON.parse(sql(tx(`select crm.recorrido_atender_oficina_fn(${q(randomUUID())},${q(f.lead)},'interesado','Entrevista real de banco',null,1000,'PEN');`)));
  f.actividad = oficina.actividad_id;
  const persona = JSON.parse(sql(tx(`select crm.preparar_persona_lead_inversion_fn(${q(f.lead)},'DNI',${q(f.documento)},${q('BANCO CARRERA ' + nombre)});`)));
  const fecha = sql("select (clock_timestamp() at time zone 'America/Lima')::date");
  const vence = sql(`select private.coopac_validar_condiciones(${q(fecha)},12,12)`);
  f.datos = { inversionista_id: persona.inversionista_id, lead_id: f.lead, empresa: 'qorilazo', monto: 1000,
    moneda: 'PEN', fecha_comercial: fecha, vence_en: vence, plazo_meses: 12, tasa_anual: 12,
    numero_transaccion: 'CARRERA-' + f.solicitud, referencia: 'BANCO SINTETICO',
    evidencia: { ruta: `${persona.inversionista_id}/${f.solicitud}/comprobante.pdf` } };
  sql(tx(`select crm.preparar_inversion_fn(${q(f.solicitud)},${q(JSON.stringify(f.datos))});`));
  sql(`insert into storage.objects(bucket_id,name,metadata) values('f4-comprobantes',${q(f.datos.evidencia.ruta)},'{"size":12,"mimetype":"application/pdf"}');`);
  return f;
}
let creada = false;
try {
  banco(`create database ${db} template template0 owner postgres;`); creada = true;
  const dump = (...secciones) => {
    const r = spawnSync('docker', ['exec', contenedor, 'pg_dump', '-U', 'supabase_admin', '-d', 'postgres', '--no-comments',
      ...secciones.map(s => '--section=' + s)], { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
    assert.equal(r.status, 0, r.stderr); return r.stdout;
  };
  sql(dump('pre-data', 'data'));
  // El banco copió configuraciones públicas sin las personas que las publicaron.
  // Completar SOLO en esta copia sus FK con perfiles ficticios e inactivos antes
  // de restaurar constraints/triggers. No cambia funciones ni salta checks del ensayo.
  const referencias = banco(`select string_agg(format('select %I as id from %s where %I is not null',a.attname,c.conrelid::regclass,a.attname),' union ')
    from pg_constraint c join pg_attribute a on a.attrelid=c.conrelid and a.attnum=c.conkey[1]
    where c.contype='f' and c.confrelid='public.perfiles'::regclass and cardinality(c.conkey)=1
      and c.conrelid::regclass::text like 'crm.%';`);
  sql(`create temporary table autores_ficticios as select distinct r.id from (${referencias}) r
    where not exists(select 1 from public.perfiles p where p.id=r.id);
    insert into auth.users(id) select a.id from autores_ficticios a where not exists(select 1 from auth.users u where u.id=a.id);
    insert into public.perfiles(id,nombre_completo,rol,activo,tipo_documento)
      select id,'AUTOR FICTICIO DE CONFIGURACION','comercial',false,'DNI' from autores_ficticios;`);
  sql(dump('post-data'));
  // Replay real de fase 5 desde las definiciones de fase 3, SOLO en esta copia.
  // No basta con reemplazar helpers a mano: se ejecutan ambos archivos completos.
  const originales = ['crm.preparar_persona_lead_inversion_fn', 'crm.confirmar_inversion_revisada_fn',
    'crm.acceso_inversion_fn', 'private.conversion_lead_con_inversion'].map(nombre =>
    archivo(`../../../docs/plans/recorrido-lead-hechos/evidencia/${nombre}.sql`).trimEnd() + ';');
  const fase2 = archivo('../../migrations/20261019001500_crm_recorrido_evaluacion.sql');
  for (const firma of ['private.recorrido_control_guard()', 'crm.recorrido_configurar_fn(', 'crm.recorrido_leads_fn(']) {
    const start = fase2.indexOf('create function ' + firma), end = fase2.indexOf('end $$;', start) + 7;
    assert(start >= 0 && end > start);
    originales.push(fase2.slice(start, end).replace('create function', 'create or replace function'));
  }
  sql(`begin;set local role postgres;
    drop trigger trg_solicitudes_recorrido on crm.inversion_solicitudes;
    drop trigger trg_leads_zzzz_recorrido_insert on crm.leads;
    drop function private.recorrido_solicitud_guard(),private.recorrido_insert_convertido_guard();
    ${originales.join('\n')}
    drop function private.recorrido_exigir(uuid,text);
    alter table crm.inversion_solicitudes drop column recorrido_confirmado;
    commit;`);
  sql('set role postgres;\n' + archivo('../../migrations/20261019001700_crm_recorrido_conversion.sql'));
  sql('set role postgres;\n' + archivo('../../migrations/20261019001701_crm_recorrido_conversion_hardening.sql'));
  console.log('PASS: replay íntegro de fase 5 + hardening desde los contratos previos, en copia desechable.');
  const fase3 = archivo('../../migrations/20261019001600_crm_recorrido_oficina.sql');
  const extraer = (fuente, prefijo) => {
    const a = fuente.indexOf(prefijo), b = fuente.indexOf('end $$;', a) + 7;
    assert(a >= 0 && b > a);
    return fuente.slice(a, b).replace(/^create function/, 'create or replace function');
  };
  sql(`begin;set local role postgres;
    ${extraer(fase3, 'create or replace function private.recorrido_capturar_actividad()')}
    ${extraer(fase2, 'create function private.recorrido_serializar_invalidacion()')}
    alter table crm.actividad_ciclo_contexto
      drop constraint actividad_ciclo_contexto_estado_ciclo_check,
      drop constraint actividad_ciclo_contexto_check1,
      add constraint actividad_ciclo_contexto_estado_ciclo_check check (estado_ciclo in ('ciclo','base_sin_ciclo')),
      add constraint actividad_ciclo_contexto_check1 check ((estado_ciclo='ciclo' and ciclo_n is not null)
        or (estado_ciclo='base_sin_ciclo' and ciclo_n is null));
    commit;`);
  sql('set role postgres;\n' + archivo('../../migrations/20261019001702_crm_recorrido_revision_pr.sql'));
  sql('set role postgres;\n' + archivo('../../migrations/20261019001703_crm_recorrido_revision_pr_hardening.sql'));
  console.log('PASS: replay íntegro de correcciones del PR + hardening, sin alterar migraciones anteriores.');
  sql("insert into storage.buckets(id,name,public) values('f4-comprobantes','f4-comprobantes',false) on conflict(id) do nothing;");
  sql(modo('exigir'));
  const a = fixture('CONFIRMAR PRIMERO');
  const c1 = sesion('confirmar_a'); c1.enviar(`${inicio}${confirmar(a)}\n\\echo LISTO`); await marcador(c1);
  const i1 = sesion('invalidar_b'); await i1.cerrar(`begin;${invalidar(a)}commit;`);
  assert.notEqual(i1.codigo, 0); assert.match(i1.error, /55P03/);
  correcto(await c1.cerrar('commit;'));
  assert.equal(sql(`select metadata ? 'deshecho_en' from crm.actividades where id=${q(a.actividad)}`), 'f');
  assert.equal(sql(`select recorrido_confirmado->>'asistencia_id' from crm.inversion_solicitudes where id=${q(a.solicitud)}`), a.actividad);
  console.log('PASS: confirmar retiene evidencia; invalidación inversa rechaza sin deadlock ni pérdida.');

  const b = fixture('INVALIDAR PRIMERO');
  const i2 = sesion('invalidar_a'); i2.enviar(`begin;${invalidar(b)}\n\\echo LISTO`); await marcador(i2);
  const c2 = sesion('confirmar_b'); await c2.cerrar(tx(confirmar(b)));
  assert.notEqual(c2.codigo, 0); assert.match(c2.error, /55P03/);
  correcto(await i2.cerrar('commit;'));
  const rechazo = ejecutar(tx(confirmar(b)));
  assert.notEqual(rechazo.status, 0); assert.match(rechazo.stderr, /P0409: Antes de convertir/);
  assert.equal(sql(`select estado||':'||(inversion_id is null)::text from crm.inversion_solicitudes where id=${q(b.solicitud)}`), 'preparada:true');
  console.log('PASS: invalidación gana; el reintento lee hechos vigentes y conserva el borrador sin inversión.');

  for (const rollback of [false, true]) {
    const f = fixture(rollback ? 'ROLLBACK PERDIDO' : 'DOBLE CONFIRMACION');
    const primera = sesion(rollback ? 'rollback_a' : 'doble_a');
    primera.enviar(`${inicio}${confirmar(f)}\n\\echo LISTO`); await marcador(primera);
    const segunda = sesion(rollback ? 'rollback_b' : 'doble_b');
    segunda.enviar(`${inicio}${confirmar(f)}\n\\echo LISTO`); await esperaLock(segunda);
    correcto(await primera.cerrar(rollback ? 'rollback;' : 'commit;'));
    await marcador(segunda); correcto(await segunda.cerrar('commit;'));
    const r1 = respuesta(primera), r2 = respuesta(segunda);
    if (rollback) assert.notEqual(r1.inversion_id, r2.inversion_id);
    else { assert.equal(r1.inversion_id, r2.inversion_id); assert.equal(r2.reintento, true); }
    assert.equal(sql(`select count(*) from crm.cierres_externos where numero_transaccion=upper(${q(f.datos.numero_transaccion)})`), '1');
    assert.equal(sql(`select count(*) from crm.inversiones where id=${q(r2.inversion_id)}`), '1');
    console.log(rollback ? 'PASS: confirmación revertida mientras otro envío espera crea una sola inversión al recuperar.'
      : 'PASS: confirmación simultánea con respuesta perdida devuelve la misma inversión, sin duplicar.');
  }

  const f = fixture('CAMBIO DE MODO'); sql(invalidar(f));
  const revision = Number(sql('select revision from crm.recorrido_control where id'));
  const cambiar = sesion('modo_a');
  cambiar.enviar(`begin;set local role authenticated;set local request.jwt.claim.sub=${q(gerente)};
    select crm.recorrido_configurar_fn('observacion','Rollback comercial concurrente del banco',${revision});\n\\echo LISTO`);
  await marcador(cambiar);
  const confirmarModo = sesion('modo_b'); confirmarModo.enviar(`${inicio}${confirmar(f)}\n\\echo LISTO`);
  await esperaLock(confirmarModo); correcto(await cambiar.cerrar('commit;'));
  await marcador(confirmarModo); correcto(await confirmarModo.cerrar('commit;'));
  assert.equal(sql(`select recorrido_confirmado->>'modo' from crm.inversion_solicitudes where id=${q(f.solicitud)}`), 'observacion');
  assert.equal(sql(`select recorrido_confirmado->>'exigible' from crm.inversion_solicitudes where id=${q(f.solicitud)}`), 'false');
  console.log('PASS: cambio de modo concurrente serializado; fotografía refleja la decisión confirmada.');
} finally {
  for (const s of sesiones) if (s.codigo === null) {
    banco(`select pg_terminate_backend(pid) from pg_stat_activity where datname=${q(db)} and application_name=${q(s.app)};`);
    await s.cerrar();
  }
  if (creada) {
    assert.match(db, /^recorrido_carrera_[a-f0-9]{12}$/);
    banco(`drop database ${db} with (force);`);
    console.log('Base desechable eliminada; modo/corte del banco principal intactos.');
  }
}
