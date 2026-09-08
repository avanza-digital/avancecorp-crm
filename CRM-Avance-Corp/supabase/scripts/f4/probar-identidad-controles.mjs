import assert from 'node:assert/strict';
import { randomInt, randomUUID } from 'node:crypto';
import { writeFileSync } from 'node:fs';
import { crearHandlerAccesoInversion } from '../../../../_supabase_functions/functions/crm-inversion-portal/handler.mjs';
import { sql, literal as q, leer, guardar, sesion, rpc, handlerEnBanco } from './banco-local.mjs';
import { comprobar as ok, prepararPersonaPortal, llamarHandler } from './portal-fixture.mjs';
import { crearCanonica, fusionar, firmaIntencion, firmaSaga } from './fusion-fixture.mjs';
import { retener, esperarActividad } from './candados-prueba.mjs';

const f = leer('fixtures.json');
const t = await sesion(f.usuarios.vendedor, f.password);
const gerente = await sesion(f.usuarios.gerencia, f.password);
const nuevo = await sesion(f.usuarios.ajeno, f.password);
const normal = handlerEnBanco(crearHandlerAccesoInversion);
const ejecucion = randomUUID();
const casos = [];
const pruebas = [];
const bandera = sql("select activo from crm.multiempresa_flags where nombre='inversiones_escritura'");
const claims = uid => `set local role authenticated; select set_config('request.jwt.claims',${q(JSON.stringify({ sub: uid, role: 'authenticated' }))},true);`;
const canonica = () => crearCanonica({ gerente, responsable: f.usuarios.ajeno.id, creador: f.usuarios.gerencia.id });
const preparar = async etiqueta => {
  const c = await prepararPersonaPortal({ vendedor: f.usuarios.vendedor.id, token: t, etiqueta });
  ok(await rpc('preparar_inversion_fn', { p_clave: c.solicitud, p_datos: c.datos }, t), 'Preparar control de identidad');
  c.perfil = ok(await llamarHandler(normal, c.solicitud, t), 'Completar acceso antes de la carrera').perfil_id;
  casos.push(c);
  guardar(`identidad-controles-${ejecucion}.json`, casos);
  return c;
};
const revisar = c => rpc('revisar_solicitud_inversion_fn', { p_solicitud: c.solicitud,
  p_responsable_revisado: f.usuarios.ajeno.id, p_revision_esperada: 0,
  p_motivo: 'Revisión ficticia después de corregir o fusionar la identidad' }, nuevo);
const prepararCorreccion = c => {
  do { c.documentoNuevo = `92${String(randomInt(1_000_000)).padStart(6, '0')}`; }
  while (sql(`select count(*) from crm.inversionista_identificadores where documento_normalizado=${q(c.documentoNuevo)}`) !== '0');
  c.identificadorAnterior = sql(`select id from crm.inversionista_identificadores where inversionista_id=${q(c.persona)}
    and documento_normalizado=${q(c.documento)} and estado='vigente'`);
  return { p_inversionista: c.persona, p_tipo: 'DNI', p_documento: c.documentoNuevo,
    p_identificador_anterior: c.identificadorAnterior, p_motivo: 'Corrección ficticia concurrente con la confirmación' };
};
const snapshot = c => JSON.parse(sql(`select snapshot from private.contrato_pdf_jobs where contrato_id=${q(c.resultado.fuente.id)}`));
const unaInversion = (c, actual = c.persona) => {
  assert.equal(sql(`select count(*) from crm.inversiones where inversionista_id=${q(actual)} and contrato_id is not null`), '1');
  assert.equal(sql(`select count(*) from auth.users where id=${q(c.perfil)}`), '1');
  assert.equal(sql(`select count(*) from crm.leads where inversionista_id=${q(actual)}`), '1');
};

sql("update crm.multiempresa_flags set activo=true where nombre='inversiones_escritura'");
try {
  for (const primera of ['correccion', 'confirmacion']) {
    const c = await preparar(`carrera_documento_${primera}`);
    const correccion = prepararCorreccion(c);
    const intencionAntes = firmaIntencion(c);
    const sagaAntes = firmaSaga(c);
    const sentencia = primera === 'correccion'
      ? `${claims(f.usuarios.gerencia.id)} select crm.corregir_documento_inversionista_fn(${q(c.persona)},'DNI',${q(c.documentoNuevo)},${q(correccion.p_motivo)},${q(c.identificadorAnterior)})`
      : `${claims(f.usuarios.vendedor.id)} select crm.confirmar_inversion_fn(${q(c.solicitud)})`;
    const liberar = await retener(sentencia);
    const concurrente = primera === 'correccion'
      ? rpc('confirmar_inversion_fn', { p_solicitud: c.solicitud }, t)
      : rpc('corregir_documento_inversionista_fn', correccion, gerente);
    try {
      await esperarActividad(`a.wait_event_type='Lock' and a.query like '%${primera === 'correccion' ? 'confirmar_inversion_fn' : 'corregir_documento_inversionista_fn'}%'`, 1);
    } finally { await liberar(); }
    const r = await concurrente;
    if (primera === 'correccion') {
      assert.equal(r.data.code, '40001');
      assert.equal(sql(`select count(*) from crm.inversiones where inversionista_id=${q(c.persona)} and contrato_id is not null`), '0');
    } else ok(r, 'Corregir después de la confirmación concurrente');
    c.resultado = ok(await rpc('confirmar_inversion_fn', { p_solicitud: c.solicitud }, t), 'Confirmar/repetir después de liberar candados');
    assert.equal(snapshot(c).titular.documento, primera === 'correccion' ? c.documentoNuevo : c.documento);
    assert.equal(sql(`select dni from public.perfiles where id=${q(c.perfil)}`), c.documentoNuevo);
    assert.equal(firmaIntencion(c), intencionAntes);
    assert.equal(firmaSaga(c), sagaAntes);
    unaInversion(c);
    pruebas.push({ caso: `documento_${primera}_primero`, coincidenciaPostgresObservada: true,
      sinFinalParcialNiDuplicado: true, snapshotSegunOrdenReal: true, sagaIntacta: true });
    guardar(`identidad-controles-${ejecucion}.json`, casos);
    console.log(`Conforme: carrera documento/confirmación, ${primera} primero y recuperación sin duplicados.`);
  }

  for (const primera of ['fusion', 'confirmacion']) {
    const c = await preparar(`carrera_fusion_${primera}`);
    c.canonica = await canonica();
    const vista = ok(await rpc('fusion_previsualizar_fn', { p_perdedora: c.persona, p_canonica: c.canonica.persona }, gerente), 'Previsualizar antes de la carrera');
    assert.equal(vista.viable, true);
    const fusion = { p_perdedora: c.persona, p_canonica: c.canonica.persona,
      p_hash: vista.hash, p_motivo: 'Fusión ficticia concurrente con confirmar inversión' };
    const intencionAntes = firmaIntencion(c);
    const sagaAntes = firmaSaga(c);
    const sentencia = primera === 'fusion'
      ? `${claims(f.usuarios.gerencia.id)} select crm.fusionar_inversionistas_fn(${q(c.persona)},${q(c.canonica.persona)},${q(fusion.p_motivo)},${q(vista.hash)})`
      : `${claims(f.usuarios.vendedor.id)} select crm.confirmar_inversion_fn(${q(c.solicitud)})`;
    const liberar = await retener(sentencia);
    const concurrente = primera === 'fusion'
      ? rpc('confirmar_inversion_fn', { p_solicitud: c.solicitud }, t)
      : rpc('fusionar_inversionistas_fn', fusion, gerente);
    try {
      await esperarActividad(`a.wait_event_type='Lock' and a.query like '%${primera === 'fusion' ? 'confirmar_inversion_fn' : 'fusionar_inversionistas_fn'}%'`, 1);
    } finally { await liberar(); }
    const r = await concurrente;
    if (primera === 'fusion') {
      assert.equal(r.data.code, '40001');
      assert.equal((await rpc('confirmar_inversion_fn', { p_solicitud: c.solicitud }, t)).data.code, '42501');
      assert.equal(sql(`select count(*) from crm.inversiones where inversionista_id=${q(c.canonica.persona)} and contrato_id is not null`), '0');
      ok(await revisar(c), 'Revisar con equipo actual después de la carrera');
    } else {
      assert.equal(r.data.code, 'P0409');
      assert.match(r.data.message, /previsualización caducó/);
      assert.equal(sql(`select estado from crm.inversionistas where id=${q(c.persona)}`), 'activo');
      c.fusion = await fusionar(c.persona, c.canonica.persona, gerente);
    }
    c.resultado = ok(await rpc('confirmar_inversion_fn', { p_solicitud: c.solicitud }, nuevo), 'Confirmar/repetir después de la fusión');
    assert.equal(c.resultado.inversionista_id, c.canonica.persona);
    assert.equal(firmaIntencion(c), intencionAntes);
    assert.equal(firmaSaga(c), sagaAntes);
    assert.equal(sql(`select analista_cierre_id from public.contratos where id=${q(c.resultado.fuente.id)}`),
      primera === 'fusion' ? f.usuarios.ajeno.id : f.usuarios.vendedor.id);
    unaInversion(c, c.canonica.persona);
    pruebas.push({ caso: `fusion_${primera}_primero`, coincidenciaPostgresObservada: true,
      revisionOHashCaducadoRespetados: true, unaInversionEnCanonica: true, atribucionSegunConfirmacion: true });
    guardar(`identidad-controles-${ejecucion}.json`, casos);
    console.log(`Conforme: carrera fusión/confirmación, ${primera} primero y resultado en la canónica.`);
  }

  const mixta = await preparar('documento_y_fusion');
  ok(await rpc('corregir_documento_inversionista_fn', prepararCorreccion(mixta), gerente), 'Corregir antes de fusionar');
  const intencionMixta = firmaIntencion(mixta);
  const sagaMixta = firmaSaga(mixta);
  mixta.canonica = await canonica();
  mixta.fusion = await fusionar(mixta.persona, mixta.canonica.persona, gerente);
  ok(await revisar(mixta), 'Revisar después de corrección y fusión');
  assert.equal(firmaIntencion(mixta), intencionMixta);
  assert.equal(firmaSaga(mixta), sagaMixta);
  assert.equal(ok(await llamarHandler(normal, mixta.solicitud, nuevo), 'Reutilizar Auth con contexto histórico').perfil_id, mixta.perfil);
  mixta.resultado = ok(await rpc('confirmar_inversion_fn', { p_solicitud: mixta.solicitud }, nuevo), 'Confirmar tras ambos cambios');
  assert.equal(snapshot(mixta).titular.documento, mixta.documentoNuevo);
  unaInversion(mixta, mixta.canonica.persona);
  pruebas.push({ caso: 'documento_y_fusion', contextoHistoricoNoBloqueaRevisionTerminal: true,
    accesoOriginalConDocumentoCorregido: true, unaInversion: true });

  // Caso REAL del banco anterior a esta ampliación. No se borra la propiedad
  // nueva de un contexto para fingir compatibilidad con el formato previo.
  const anterior = JSON.parse(sql(`select coalesce((select jsonb_build_object('persona',s.inversionista_id,
    'solicitud',s.id,'datos',s.datos,'perfil',i.perfil_id,'resultado',s.resultado,'lead',s.resultado->>'lead_id')
    from crm.inversion_solicitudes s join crm.inversionistas i on i.id=s.inversionista_id
    join crm.multiempresa_idempotencia m on m.clave='auth_persona:'||i.id::text and m.resultado->>'claim_id'=s.auth_claim_id::text
    where s.estado='confirmada' and i.estado='activo' and i.responsable_relacion_id=${q(f.usuarios.vendedor.id)}
      and s.auth_contexto is not null and not (s.auth_contexto ? 'inversionista_id') and m.resultado->>'estado'='enlazado'
      and s.datos#>>'{alta_portal,correo}' like 'f4.portal.%@pruebas.example'
    order by s.creado_en,s.id limit 1),'null'::jsonb)`));
  assert(anterior, 'Falta un caso histórico del banco, con contexto Auth anterior sin inversionista_id');
  casos.push(anterior);
  anterior.canonica = await canonica();
  const firmaAnterior = firmaIntencion(anterior);
  const sagaAnterior = firmaSaga(anterior);
  anterior.fusion = await fusionar(anterior.persona, anterior.canonica.persona, gerente);
  assert.equal(ok(await llamarHandler(normal, anterior.solicitud, nuevo), 'Recuperar formato Auth anterior tras fusión').perfil_id, anterior.perfil);
  const replay = ok(await rpc('confirmar_inversion_fn', { p_solicitud: anterior.solicitud }, nuevo), 'Repetir inversión anterior a la ampliación');
  assert.equal(replay.inversion_id, anterior.resultado.inversion_id);
  assert.equal(replay.inversionista_id, anterior.canonica.persona);
  assert.equal(firmaIntencion(anterior), firmaAnterior);
  assert.equal(firmaSaga(anterior), sagaAnterior);
  unaInversion(anterior, anterior.canonica.persona);
  pruebas.push({ caso: 'contexto_auth_anterior_real', sinFabricarFormato: true,
    mismoAuthYFuente: true, contextoYClaimSinReescribir: true });
  guardar(`identidad-controles-${ejecucion}.json`, casos);
  writeFileSync(new URL(`../evidencia-f4/identidad-controles-${ejecucion}.json`, import.meta.url), JSON.stringify({
    entorno: 'avancecorp-f4-bank', ejecucion, terminadoEn: new Date().toISOString(), pruebas,
    limite: 'Carreras de corrección/fusión con la confirmación y compatibilidad de solicitudes históricas del banco. No cubre todos los lectores heredados ni el worker PDF.',
  }, null, 2) + '\n');
  console.log('Conforme: corrección seguida de fusión y recuperación de un contexto Auth anterior real.');
} finally {
  sql(`update crm.multiempresa_flags set activo=${bandera === 't'} where nombre='inversiones_escritura'`);
}
