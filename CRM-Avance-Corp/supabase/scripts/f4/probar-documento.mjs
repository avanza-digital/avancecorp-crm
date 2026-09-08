import { entorno } from './banco-local.mjs';
import assert from 'node:assert/strict';
import { createHash, randomInt, randomUUID } from 'node:crypto';
import { writeFileSync } from 'node:fs';
import { crearHandlerAccesoInversion } from '../../../../_supabase_functions/functions/crm-inversion-portal/handler.mjs';
import { sql, literal as q, leer, guardar, sesion, rpc, handlerEnBanco } from './banco-local.mjs';
import { comprobar as ok, prepararPersonaPortal, llamarHandler, estadoAcceso } from './portal-fixture.mjs';

// La corrección publicada bloquea todo claim Auth no enlazado. Se prueba el
// recorrido permitido: recuperar ese acceso, corregir por Gerencia y confirmar
// la MISMA solicitud. No se fuerzan documentos, perfiles, estados ni leases.
const f = leer('fixtures.json');
const t = await sesion(f.usuarios.vendedor, f.password);
const gerente = await sesion(f.usuarios.gerencia, f.password);
const normal = handlerEnBanco(crearHandlerAccesoInversion);
const ejecucion = randomUUID();
const pruebas = [];
const casos = [];
const bandera = sql("select activo from crm.multiempresa_flags where nombre='inversiones_escritura'");
const original = leer('functions-prod.json').find(x => x.schema === 'crm' && x.nombre === 'corregir_documento_inversionista_fn');
assert(original);
const huellaCorreccion = createHash('md5').update(original.body).digest('hex');
assert.equal(sql("select md5(prosrc) from pg_proc where oid='crm.corregir_documento_inversionista_fn(uuid,text,text,text,uuid)'::regprocedure"), huellaCorreccion);

function documentoDisponible(tipo = 'DNI') {
  let documento;
  do { documento = `${tipo === 'DNI' ? '93' : '001'}${String(randomInt(1_000_000)).padStart(6, '0')}`; }
  while (sql(`select count(*) from crm.inversionista_identificadores where documento_normalizado=${q(documento)}`) !== '0');
  return documento;
}
const firmaSolicitud = c => sql(`select md5(jsonb_build_object('datos',datos,'hash',hash_payload,'contexto',auth_contexto,'claim',auth_claim_id)::text)
  from crm.inversion_solicitudes where id=${q(c.solicitud)}`);
const saga = c => sql(`select coalesce((select md5(to_jsonb(m)::text) from crm.multiempresa_idempotencia m
  where clave=${q(`auth_persona:${c.persona}`)}),'ausente')`);
const estadoIdentidad = c => sql(`select md5(jsonb_build_object(
  'persona',(select to_jsonb(i) from crm.inversionistas i where id=${q(c.persona)}),
  'documentos',(select jsonb_agg(to_jsonb(d) order by d.id) from crm.inversionista_identificadores d where inversionista_id=${q(c.persona)}),
  'lead',(select to_jsonb(l) from crm.leads l where id=${q(c.lead)}),
  'perfil',(select to_jsonb(p) from public.perfiles p where id=(select perfil_id from crm.inversionistas where id=${q(c.persona)})),
  'operaciones',(select jsonb_agg(to_jsonb(o) order by o.id) from crm.inversionista_operaciones o where inversionista_id=${q(c.persona)})
  )::text)`);
const corregir = (c, token = gerente) => rpc('corregir_documento_inversionista_fn', {
  p_inversionista: c.persona, p_tipo: c.tipoNuevo, p_documento: c.documentoNuevo,
  p_motivo: 'Corrección ficticia del documento verificado durante el ensayo F4',
  p_identificador_anterior: c.identificadorAnterior,
}, token);

sql("update crm.multiempresa_flags set activo=true where nombre='inversiones_escritura'");
try {
  for (const corte of ['sin_auth', 'reclamar', 'auth', 'registrar_auth', 'crear_perfil', 'enlazar', 'confirmada']) {
    const c = await prepararPersonaPortal({ vendedor: f.usuarios.vendedor.id, token: t, etiqueta: `documento_${corte}` });
    c.tipoNuevo = corte === 'crear_perfil' ? 'CE' : 'DNI';
    c.documentoNuevo = documentoDisponible(c.tipoNuevo);
    c.identificadorAnterior = sql(`select id from crm.inversionista_identificadores
      where inversionista_id=${q(c.persona)} and estado='vigente' and documento_normalizado=${q(c.documento)}`);
    casos.push(c);
    guardar(`documento-${ejecucion}.json`, casos);
    ok(await rpc('preparar_inversion_fn', { p_clave: c.solicitud, p_datos: c.datos }, t), 'Preparar antes de corregir documento');
    const cierreAntes = sql(`select md5(to_jsonb(ce)::text) from crm.cierres_externos ce where lead_id=${q(c.lead)}`);
    if (corte === 'reclamar') {
      const r = ok(await rpc('acceso_inversion_fn', { p_solicitud: c.solicitud, p_paso: 'reclamar' }, t), 'Reclamar antes de crear Auth');
      c.tokenSaga = r.token;
      assert.match(c.tokenSaga, /^[a-f0-9]{48}$/);
    } else if (corte === 'confirmada') {
      c.perfil = ok(await llamarHandler(normal, c.solicitud, t), 'Completar acceso antes de confirmar').perfil_id;
      c.resultado = ok(await rpc('confirmar_inversion_fn', { p_solicitud: c.solicitud }, t), 'Confirmar antes de corregir');
    } else if (corte !== 'sin_auth') {
      let perdida = false;
      const conCorte = handlerEnBanco(crearHandlerAccesoInversion, async (url, opciones) => {
        const r = await fetch(url, opciones);
        const paso = url.endsWith('/rest/v1/rpc/acceso_inversion_fn') ? JSON.parse(opciones.body).p_paso : null;
        if (!perdida && r.ok && ((corte === 'auth' && url.endsWith('/auth/v1/admin/users')) || paso === corte)) {
          await r.clone().json(); perdida = true;
          throw new TypeError('Respuesta real perdida antes de solicitar corrección documental');
        }
        return r;
      });
      const r = await llamarHandler(conCorte, c.solicitud, t);
      assert.equal(r.status, 503);
      assert.equal(perdida, true);
      c.tokenSaga = r.data.token;
      assert.match(c.tokenSaga, /^[a-f0-9]{48}$/);
    }
    const identidadAntes = estadoIdentidad(c);
    const contenidoAntes = firmaSolicitud(c);
    const sagaAntes = saga(c);
    assert.equal((await corregir(c, t)).data.code, '42501', 'El vendedor no puede corregir el documento');
    const pendiente = ['reclamar', 'auth', 'registrar_auth', 'crear_perfil'].includes(corte);
    if (pendiente) {
      const rechazo = await corregir(c);
      assert.equal(rechazo.data.code, 'P0409');
      assert.match(rechazo.data.message, /alta o conversión en curso/);
      assert.equal(estadoIdentidad(c), identidadAntes, 'El rechazo cambió la identidad o su historial');
      assert.equal(firmaSolicitud(c), contenidoAntes, 'El rechazo cambió la intención original');
      assert.equal(saga(c), sagaAntes, 'El rechazo alteró el proceso Auth');
      assert.equal(estadoAcceso(c.solicitud).inversion, null);
      c.perfil = ok(await llamarHandler(normal, c.solicitud, t, c.tokenSaga), 'Recuperar acceso antes de corregir documento').perfil_id;
    }
    const contextoAntesDeCorregir = firmaSolicitud(c);
    const sagaAntesDeCorregir = saga(c);
    const authAntes = sql(`select md5(encrypted_password) from auth.users where lower(email)=${q(c.datos.alta_portal.correo)}`);
    const contratoAntes = c.resultado ? sql(`select md5(to_jsonb(ct)::text) from public.contratos ct where id=${q(c.resultado.fuente.id)}`) : null;
    const jobAntes = c.resultado ? sql(`select md5(to_jsonb(j)::text) from private.contrato_pdf_jobs j where contrato_id=${q(c.resultado.fuente.id)}`) : null;
    c.correccion = ok(await corregir(c), 'Corregir mediante la puerta de Gerencia');
    assert.equal(c.correccion.estado, 'corregido');
    assert.equal(firmaSolicitud(c), contextoAntesDeCorregir, 'Corregir reescribió datos, hash o contexto Auth');
    assert.equal(saga(c), sagaAntesDeCorregir, 'Corregir reescribió la saga Auth');
    assert.equal(sql(`select md5(encrypted_password) from auth.users where lower(email)=${q(c.datos.alta_portal.correo)}`), authAntes,
      'La corrección no debe resetear automáticamente la clave (decisión del 06/09)');
    assert.equal(sql(`select estado from crm.inversionista_identificadores where id=${q(c.identificadorAnterior)}`), 'historico');
    assert.equal(sql(`select count(*) from crm.inversionista_identificadores where inversionista_id=${q(c.persona)}
      and documento_normalizado=${q(c.documentoNuevo)} and tipo_documento=${q(c.tipoNuevo)} and estado='vigente' and verificado`), '1');
    assert.equal(sql(`select count(*) from crm.inversionista_operaciones where id=${q(c.correccion.operacion_id)}
      and identificador_anterior_id=${q(c.identificadorAnterior)} and identificador_nuevo_id=${q(c.correccion.identificador_nuevo_id)}
      and por=${q(f.usuarios.gerencia.id)}`), '1');
    c.perfil = ok(await llamarHandler(normal, c.solicitud, t, c.tokenSaga), 'Reutilizar el acceso con documento corregido').perfil_id;
    const actual = JSON.parse(sql(`select jsonb_build_object('documento',dni,'tipo',tipo_documento,'responsable',asesor_perfil_id,
      'cambiarClave',debe_cambiar_password) from public.perfiles where id=${q(c.perfil)}`));
    assert.deepEqual(actual, { documento: c.documentoNuevo, tipo: c.tipoNuevo,
      responsable: f.usuarios.vendedor.id, cambiarClave: true });
    const preparada = ok(await rpc('preparar_inversion_fn', { p_clave: c.solicitud, p_datos: c.datos }, t), 'Repetir el contenido original');
    assert.equal(preparada.solicitud_id, c.solicitud);
    assert.equal(preparada.necesita_portal, false);
    const confirmada = ok(await rpc('confirmar_inversion_fn', { p_solicitud: c.solicitud }, t), 'Confirmar la misma inversión tras la corrección');
    if (c.resultado) {
      assert.equal(confirmada.inversion_id, c.resultado.inversion_id);
      assert.equal(sql(`select md5(to_jsonb(ct)::text) from public.contratos ct where id=${q(c.resultado.fuente.id)}`), contratoAntes);
      assert.equal(sql(`select md5(to_jsonb(j)::text) from private.contrato_pdf_jobs j where contrato_id=${q(c.resultado.fuente.id)}`), jobAntes,
        'La corrección y el replay reescribieron la reserva documental histórica');
    }
    c.resultado = confirmada;
    const snapshot = JSON.parse(sql(`select snapshot from private.contrato_pdf_jobs where contrato_id=${q(confirmada.fuente.id)}`));
    assert.equal(snapshot.titular.id, c.perfil);
    assert.equal(snapshot.titular.documento, corte === 'confirmada' ? c.documento : c.documentoNuevo);
    assert.equal(snapshot.titular.tipoDocumento, corte === 'confirmada' ? 'DNI' : c.tipoNuevo);
    assert.equal(sql(`select analista_cierre_id from public.contratos where id=${q(confirmada.fuente.id)}`), f.usuarios.vendedor.id);
    assert.equal(sql(`select md5(to_jsonb(ce)::text) from crm.cierres_externos ce where lead_id=${q(c.lead)}`), cierreAntes,
      'El antecedente económico debe conservar su documento e historia');
    assert.equal(sql(`select count(*) from auth.users where lower(email)=${q(c.datos.alta_portal.correo)}`), '1');
    assert.equal(sql(`select count(*) from crm.leads where inversionista_id=${q(c.persona)}`), '1');
    assert.equal(sql(`select count(*) from crm.inversiones where inversionista_id=${q(c.persona)} and contrato_id is not null`), '1');
    assert.equal(sql(`select count(*) from public.cronograma_pagos where contrato_id=${q(confirmada.fuente.id)}`), '13');
    const tokenCliente = await sesion({ id: c.perfil, email: c.datos.alta_portal.correo }, corte === 'sin_auth' ? c.documentoNuevo : c.documento);
    assert(tokenCliente, 'El acceso original sigue operativo sin reset automático');
    pruebas.push({ corte, tipoNuevo: c.tipoNuevo, correccionReservadaAGerencia: true,
      claimPendienteBloqueaCorreccionSinEfectos: pendiente, recuperacionAntesDeCorregir: pendiente,
      mismaSolicitudConDocumentoCorregido: true, historiaEconomicaYReservaPreviaConservadas: true,
      accesoClaveYAtribucionConservados: true, sinDuplicados: true });
    guardar(`documento-${ejecucion}.json`, casos);
    console.log(`Conforme: documento en ${corte}, recuperación canónica y una sola inversión.`);
  }
  assert.equal(sql("select md5(prosrc) from pg_proc where oid='crm.corregir_documento_inversionista_fn(uuid,text,text,text,uuid)'::regprocedure"), huellaCorreccion);
  writeFileSync(new URL(`../evidencia-f4/documento-${ejecucion}.json`, import.meta.url), JSON.stringify({
    entorno, ejecucion, terminadoEn: new Date().toISOString(), pruebas,
    correccionPublicadaSinCambios: huellaCorreccion,
    limite: 'No autoriza saltar la reserva Auth. Se recupera el acceso antes de corregir, sin reset automático de clave. PDF real y fusión se comprueban aparte.',
  }, null, 2) + '\n');
} finally {
  sql(`update crm.multiempresa_flags set activo=${bandera === 't'} where nombre='inversiones_escritura'`);
}
