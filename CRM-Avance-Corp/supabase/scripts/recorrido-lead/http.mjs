// Matriz focal de recorrido: JWT emitidos por Auth y PostgREST reales.
// La preparación SQL solo fabrica datos sintéticos; las acciones se prueban por HTTP.
import assert from 'node:assert/strict';
import { randomBytes, randomInt, randomUUID } from 'node:crypto';
import { bancoHttp } from './http-banco.mjs';
import { literal as q } from './banco.mjs';
import { contratoPrueba } from '../f4/operaciones-fixture.mjs';
import { crearHandlerAccesoInversion } from '../../../../_supabase_functions/functions/crm-inversion-portal/handler.mjs';

let pruebas = 0;
const ok = (nombre, condicion = true) => { assert(condicion, nombre); pruebas++; console.log('PASS: ' + nombre); };
const exito = (r, nombre) => { assert.equal(r.status, 200, nombre + ': ' + JSON.stringify(r.data)); return r.data; };
const denegado = (r, nombre, code = '42501') => {
  assert(r.status >= 400, nombre); assert.equal(r.data.code, code, nombre + ': ' + JSON.stringify(r.data)); ok(nombre);
};

await bancoHttp(async ({ sql, http, apiUrl, fetchApi, anon, servicio }) => {
  const actores = { anon: { token: anon }, servicio: { token: servicio } };
  const clave = 'Banco-' + randomBytes(24).toString('base64url');
  const ejecucion = randomUUID();
  const rpc = (nombre, body, actor = 'vendedor') => http('/rest/v1/rpc/' + nombre,
    { body, token: actores[actor].token, schema: 'crm' });
  async function usuario(nombre, rolPortal, rolCrm, superior = null, activoPerfil = true, activoCrm = true) {
    const email = `recorrido.${ejecucion}.${nombre}@pruebas.example`;
    const alta = await http('/auth/v1/admin/users', { token: servicio, body: { email, password: clave, email_confirm: true } });
    assert([200, 201].includes(alta.status), 'Crear Auth sintético');
    const id = alta.data.id;
    sql(`insert into public.perfiles(id,nombre_completo,correo,rol,activo,debe_cambiar_password,tipo_documento,dni,telefono)
      values(${q(id)},${q('BANCO HTTP ' + nombre)},${q(email)},${q(rolPortal)},${activoPerfil},false,
        'DNI',${q(String(randomInt(94000000, 94999999)))},'999888777');
      ${rolCrm ? `insert into crm.equipo(perfil_id,rol_crm,supervisor_id,activo)
        values(${q(id)},${q(rolCrm)},${superior ? q(actores[superior].id) : 'null'},${activoCrm});` : ''}`);
    const sesion = exito(await http('/auth/v1/token?grant_type=password', { body: { email, password: clave } }), 'Login real');
    actores[nombre] = { id, token: sesion.access_token };
  }
  await usuario('gerencia', 'comercial', 'gerencia');
  await usuario('supervisor', 'analista', 'supervisor', 'gerencia');
  await usuario('ajenoSupervisor', 'analista', 'supervisor', 'gerencia');
  await usuario('vendedor', 'analista', 'vendedor', 'supervisor');
  await usuario('reemplazo', 'analista', 'vendedor', 'supervisor');
  await usuario('ajeno', 'analista', 'vendedor', 'ajenoSupervisor');
  await usuario('coordinacion', 'comercial', 'coordinador');
  await usuario('directorio', 'directorio', 'directorio');
  await usuario('sinMembresia', 'analista', null);
  await usuario('inactivoPerfil', 'comercial', 'gerencia', null, false, false);
  await usuario('inactivoCrm', 'comercial', 'gerencia', null, true, false);

  function lead(nombre, actor = 'vendedor') {
    const id = randomUUID();
    sql(`insert into crm.leads(id,nombre_completo,telefono,origen,monto_estimado,moneda,vendedor_id,creado_por)
      values(${q(id)},${q('BANCO HTTP ' + nombre)},${q(String(randomInt(970000000, 979999999)))},'oficina',1000,'PEN',
        ${q(actores[actor].id)},${q(actores.gerencia.id)});`);
    return id;
  }
  const propio = lead('PROPIO'), ajeno = lead('AJENO', 'ajeno'), antiguo = lead('ANTIGUO');
  const leer = (ids, actor = 'vendedor') => rpc('recorrido_leads_fn', { p_lead_ids: ids }, actor);
  const filas = async (ids, actor = 'vendedor') => exito(await leer(ids, actor), 'Leer recorrido').filas;
  for (const actor of ['vendedor', 'supervisor', 'ajeno', 'ajenoSupervisor', 'gerencia', 'coordinacion', 'directorio']) {
    const visibles = (await filas([propio, ajeno], actor)).map(r => r.lead_id).sort();
    const esperados = ['gerencia', 'coordinacion', 'directorio'].includes(actor) ? [propio, ajeno]
      : actor.startsWith('ajeno') ? [ajeno] : [propio];
    assert.deepEqual(visibles, esperados.sort()); ok(actor + ' obtiene exactamente su ámbito');
  }
  for (const actor of ['anon', 'servicio', 'sinMembresia', 'inactivoPerfil', 'inactivoCrm']) {
    denegado(await leer([propio], actor), actor + ' no puede consultar el recorrido');
  }
  denegado(await leer(Array.from({ length: 101 }, () => randomUUID())), 'El lote mayor a 100 se rechaza', '22023');
  const config = { p_modo: 'exigir', p_motivo: 'Ensayo de permisos en copia HTTP', p_revision: 1 };
  for (const actor of Object.keys(actores).filter(a => a !== 'gerencia')) {
    denegado(await rpc('recorrido_configurar_fn', config, actor), actor + ' no activa el bloqueo');
  }
  const control = exito(await rpc('recorrido_configurar_fn', config, 'gerencia'), 'Gerencia configura exigencia');
  ok('Solo Gerencia activa exigencia y fija corte del servidor', control.modo === 'exigir' && !!control.cohorte_desde);
  denegado(await rpc('recorrido_configurar_fn', config, 'gerencia'), 'Revisión obsoleta no sobrescribe el modo', '40001');

  const documento = () => String(randomInt(97000000, 97999999));
  const identidad = (id, doc = documento(), actor = 'vendedor') => rpc('preparar_persona_lead_inversion_fn', {
    p_lead: id, p_tipo_documento: 'DNI', p_documento: doc, p_nombre: 'BANCO HTTP PERSONA',
  }, actor);
  exito(await identidad(antiguo), 'Identidad anterior al corte');
  ok('La cohorte antigua conserva el comportamiento previo');
  const nuevo = lead('NUEVO SIN HECHOS'), doc = documento();
  const bloqueo = await identidad(nuevo, doc);
  denegado(bloqueo, 'Primera conversión sin hechos rechazada por API', 'P0409');
  assert.match(bloqueo.data.message, /asistió.*entrevista/i);
  assert.equal(sql(`select count(*) from crm.inversionista_identificadores where documento_normalizado=${q(doc)}`), '0');
  const cambio = await http(`/rest/v1/leads?id=eq.${nuevo}`, { method: 'PATCH', schema: 'crm',
    token: actores.vendedor.token, body: { etapa: 'propuesta_enviada' } });
  exito(cambio, 'Cambio de etapa permitido por el contrato vigente');
  denegado(await identidad(nuevo, doc), 'Cambiar de etapa no acredita asistencia ni entrevista', 'P0409');
  const oficina = id => ({ p_operacion_id: randomUUID(), p_lead_id: id,
    p_resultado_reunion: 'interesado', p_detalle: 'Asistió y realizamos la entrevista del banco',
    p_capital_estimado: 1000, p_moneda: 'PEN', p_siguiente: null, p_ubicacion: 'Oficina de prueba' });
  for (const actor of ['ajeno', 'ajenoSupervisor', 'coordinacion', 'directorio', 'sinMembresia', 'inactivoPerfil', 'inactivoCrm', 'anon', 'servicio']) {
    denegado(await rpc('recorrido_atender_oficina_fn', oficina(nuevo), actor), actor + ' no registra visita fuera de su permiso');
  }
  const peticion = oficina(nuevo);
  const visita = exito(await rpc('recorrido_atender_oficina_fn', peticion), 'Atender visita');
  assert.deepEqual(exito(await rpc('recorrido_atender_oficina_fn', peticion), 'Reintento de visita'), visita);
  denegado(await rpc('recorrido_atender_oficina_fn', { ...peticion, p_capital_estimado: 2000 }), 'Clave repetida con otro capital rechazada', 'P0409');
  ok('Oficina crea una sola cita y asistencia ante respuesta perdida', sql(`select count(*) from crm.tareas where lead_id=${q(nuevo)}`) === '1');
  const evaluado = (await filas([nuevo]))[0];
  ok('La API confirma dos hechos de la misma cita y del ciclo vigente', evaluado.habilita_conversion
    && evaluado.exigible && evaluado.pasos.asistencia && evaluado.pasos.entrevista
    && evaluado.evidencias.entrevista_tarea_id === visita.tarea_id && evaluado.evidencias.asistencia_id === visita.actividad_id);
  const persona = exito(await identidad(nuevo, doc), 'Identidad posterior a entrevista');
  ok('Identidad autorizada después de registrar ambos hechos', !!persona.inversionista_id);
  for (const actor of ['supervisor', 'gerencia']) {
    exito(await rpc('recorrido_atender_oficina_fn', oficina(lead(actor)), actor), actor + ' atiende visita autorizada');
    ok(actor + ' puede registrar visita dentro de su ámbito');
  }

  sql("insert into storage.buckets(id,name,public) values('f4-comprobantes','f4-comprobantes',false) on conflict(id) do nothing");
  for (const empresa of ['qorilazo', 'prodelco']) {
    const id = lead('CONVERSION ' + empresa), solicitud = randomUUID();
    const primera = exito(await rpc('recorrido_atender_oficina_fn', oficina(id)), 'Visita antes de borrador');
    const p = exito(await identidad(id), 'Persona de conversión');
    const fecha = sql("select (clock_timestamp() at time zone 'America/Lima')::date");
    const datos = { inversionista_id: p.inversionista_id, lead_id: id, empresa, monto: 1000, moneda: 'PEN',
      fecha_comercial: fecha, vence_en: sql(`select private.coopac_validar_condiciones(${q(fecha)},12,12)`),
      plazo_meses: 12, tasa_anual: 12, numero_transaccion: 'RECORRIDO-HTTP-' + solicitud,
      referencia: 'BANCO SINTETICO', evidencia: { ruta: `${p.inversionista_id}/${solicitud}/comprobante.pdf` } };
    exito(await rpc('preparar_inversion_fn', { p_clave: solicitud, p_datos: datos }), 'Preparación por HTTP');
    // Fixture del documento subido; no simula autorización ni confirmación financiera.
    sql(`insert into storage.objects(bucket_id,name,metadata) values('f4-comprobantes',${q(datos.evidencia.ruta)},'{"size":12,"mimetype":"application/pdf"}');
      update crm.actividades set metadata=metadata||jsonb_build_object('deshecho_en',clock_timestamp()) where id=${q(primera.actividad_id)};`);
    denegado(await rpc('confirmar_inversion_revisada_fn', { p_solicitud: solicitud, p_revision_datos_esperada: 0 }),
      empresa + ': invalidar entrevista bloquea la confirmación final', 'P0409');
    const conservado = JSON.parse(sql(`select jsonb_build_object('datos',datos,'estado',estado,'inversion_id',inversion_id,'prueba',recorrido_confirmado)
      from crm.inversion_solicitudes where id=${q(solicitud)}`));
    assert.deepEqual(conservado, { datos, estado: 'preparada', inversion_id: null, prueba: null });
    ok(empresa + ': rechazo conserva borrador, condiciones y referencia del comprobante');
    for (const actor of ['vendedor', 'servicio']) {
      const r = await http(`/rest/v1/inversion_solicitudes?id=eq.${solicitud}`, { method: 'PATCH', schema: 'crm',
        token: actores[actor].token, body: { recorrido_confirmado: { version: 1, exigible: false } } });
      ok(actor + ': no puede falsificar snapshot de ' + empresa, r.status >= 400);
    }
    const vigente = exito(await rpc('recorrido_atender_oficina_fn', oficina(id)), 'Nueva entrevista válida');
    const confirmada = exito(await rpc('confirmar_inversion_revisada_fn', { p_solicitud: solicitud, p_revision_datos_esperada: 0 }), 'Confirmar tras corregir hechos');
    const repetida = exito(await rpc('confirmar_inversion_revisada_fn', { p_solicitud: solicitud, p_revision_datos_esperada: 0 }), 'Reintentar confirmada');
    assert.equal(repetida.inversion_id, confirmada.inversion_id);
    const prueba = JSON.parse(sql(`select recorrido_confirmado from crm.inversion_solicitudes where id=${q(solicitud)}`));
    ok(empresa + ': confirmación guarda pareja vigente y el reintento no duplica', prueba.asistencia_id === vigente.actividad_id
      && prueba.entrevista_tarea_id === vigente.tarea_id && prueba.exigible && repetida.reintento);
  }

  // Avance: el handler oficial crea Auth/perfil por HTTP real, sin correos ni
  // un despliegue Edge. La inversión siempre se confirma con JWT del analista.
  {
    const id = lead('AVANCE'), solicitud = randomUUID();
    const visitaAvance = exito(await rpc('recorrido_atender_oficina_fn', oficina(id)), 'Visita Avance');
    const p = exito(await identidad(id), 'Persona Avance');
    const datos = { inversionista_id: p.inversionista_id, lead_id: id, empresa: 'avance',
      contrato: { moneda: 'PEN' }, cronograma: [], cuenta: {}, alta_portal: {
        correo: `avance.${solicitud}@pruebas.example`, nombre_completo: 'PERSONA SINTETICA AVANCE',
        nombres: 'PERSONA', apellidos: 'SINTETICA AVANCE', telefono: '999888777', domicilio: 'AVENIDA FICTICIA 123 LIMA',
      } };
    exito(await rpc('preparar_inversion_fn', { p_clave: solicitud, p_datos: datos }), 'Borrador Avance');
    sql(`update crm.actividades set metadata=metadata||jsonb_build_object('deshecho_en',clock_timestamp()) where id=${q(visitaAvance.actividad_id)}`);
    const handler = crearHandlerAccesoInversion({ supabaseUrl: apiUrl, anonKey: anon, serviceKey: servicio, fetchImpl: fetchApi });
    const token = randomBytes(24).toString('hex');
    const acceso = async () => {
      const respuesta = await handler(new Request(apiUrl + '/functions/v1/crm-inversion-portal', {
        method: 'POST', headers: { Authorization: 'Bearer ' + actores.vendedor.token }, body: JSON.stringify({ solicitud_id: solicitud, token }),
      }));
      return { status: respuesta.status, data: await respuesta.json() };
    };
    const nAuth = sql('select count(*) from auth.users');
    const rechazo = await acceso();
    ok('Avance: falta de entrevista impide crear Auth mediante el handler oficial', rechazo.status === 409
      && sql('select count(*) from auth.users') === nAuth && /Antes de convertir/.test(rechazo.data.error));
    const vigente = exito(await rpc('recorrido_atender_oficina_fn', oficina(id)), 'Entrevista Avance corregida');
    const alta = exito(await acceso(), 'Alta Portal Avance por HTTP real');
    const fecha = sql("select to_char(clock_timestamp() at time zone 'America/Lima','YYYY-MM-01')");
    const propuesta = contratoPrueba(alta.perfil_id, actores.vendedor.id,
      { inicio: fecha, capital: 1000, numero: `${fecha.slice(0, 4)}-01-${randomInt(900000, 999999)}` });
    delete propuesta.contrato.cliente_id; delete propuesta.contrato.analista_cierre_id;
    exito(await rpc('corregir_solicitud_inversion_fn', { p_solicitud: solicitud, p_clave: randomUUID(),
      p_revision_datos_esperada: 0, p_datos: { ...datos, ...propuesta }, p_motivo: 'Completar condiciones ficticias tras alta Portal' }), 'Condiciones Avance');
    const confirmada = exito(await rpc('confirmar_inversion_revisada_fn', { p_solicitud: solicitud, p_revision_datos_esperada: 1 }), 'Confirmación Avance');
    const prueba = JSON.parse(sql(`select recorrido_confirmado from crm.inversion_solicitudes where id=${q(solicitud)}`));
    ok('Avance: primera conversión crea contrato y conserva los hechos vigentes', !!confirmada.inversion_id
      && prueba.asistencia_id === vigente.actividad_id && prueba.entrevista_tarea_id === vigente.tarea_id && prueba.exigible);
  }

  for (const actor of ['vendedor', 'gerencia', 'servicio', 'anon']) {
    for (const tabla of ['recorrido_control', 'actividad_ciclo_contexto']) {
      const r = await http(`/rest/v1/${tabla}?select=*`, { method: 'GET', schema: 'crm', token: actores[actor].token });
      ok(`${actor} no lee directamente ${tabla}`, r.status >= 400 || (Array.isArray(r.data) && r.data.length === 0));
      const w = await http(`/rest/v1/${tabla}`, { body: tabla === 'recorrido_control' ? { id: true, modo: 'apagado' }
        : { actividad_id: visita.actividad_id, lead_id: nuevo, ciclo_n: 99 }, schema: 'crm', token: actores[actor].token });
      ok(`${actor} no escribe directamente ${tabla}`, w.status >= 400);
    }
  }
  const acl = JSON.parse(sql(`select jsonb_agg(jsonb_build_object('firma',p.oid::regprocedure::text,'segura',
    p.prosecdef and p.proowner='postgres'::regrole and p.proconfig @> array['search_path=""']
    and not exists(select 1 from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
      where a.privilege_type='EXECUTE' and a.grantee<>p.proowner)))
    from pg_proc p where p.oid in (to_regprocedure('private.recorrido_exigir(uuid,text)'),
      to_regprocedure('private.recorrido_solicitud_guard()'),to_regprocedure('private.recorrido_insert_convertido_guard()'))`));
  ok('Helpers privados tienen owner, SECURITY DEFINER, search_path y ACL cerrados', acl.length === 3 && acl.every(x => x.segura));
  const autorizados = exito(await rpc('recorrido_leads_fn', { p_lead_ids: [nuevo] }), 'Foto antes de reasignar');
  exito(await http(`/rest/v1/leads?id=eq.${nuevo}`, { method: 'PATCH', schema: 'crm', token: actores.gerencia.token,
    body: { vendedor_id: actores.ajeno.id } }), 'Reasignación por puerta existente');
  assert.deepEqual(await filas([nuevo]), []);
  denegado(await rpc('recorrido_atender_oficina_fn', peticion), 'Ni un replay permite leer tras perder ámbito');
  const reasignado = (await filas([nuevo], 'ajeno'))[0];
  ok('Reasignar conserva el ciclo y los hechos', reasignado.habilita_conversion
    && reasignado.ciclo_n === autorizados.filas[0].ciclo_n);

  const version = sql(`select actualizado_en from crm.equipo where perfil_id=${q(actores.vendedor.id)}`);
  exito(await rpc('fijar_membresia_activa_fn', { p_perfil_id: actores.vendedor.id, p_activo: false,
    p_reemplazo_id: actores.reemplazo.id, p_version_equipo: version, p_idempotencia: randomUUID() }, 'gerencia'), 'Baja real con reemplazo');
  denegado(await leer([propio]), 'El JWT previo pierde acceso al desactivar la membresía');
  denegado(await rpc('recorrido_atender_oficina_fn', oficina(propio)), 'La membresía revocada no puede atender visitas');
  ok('El reemplazo conserva acceso al lead transferido', (await filas([propio], 'reemplazo')).length === 1);
});
console.log(`HTTP/RLS recorrido: ${pruebas} comprobaciones PASS con Auth/PostgREST reales.`);
