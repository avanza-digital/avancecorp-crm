import { entorno } from './banco-local.mjs';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { writeFileSync } from 'node:fs';
import { crearHandlerAccesoInversion } from '../../../../_supabase_functions/functions/crm-inversion-portal/handler.mjs';
import { sql, literal as q, leer, guardar, sesion, rpc, handlerEnBanco } from './banco-local.mjs';
import { comprobar as ok, prepararPersonaPortal, llamarHandler, estadoAcceso } from './portal-fixture.mjs';

const f = leer('fixtures.json');
const t = await sesion(f.usuarios.vendedor, f.password);
const gerente = await sesion(f.usuarios.gerencia, f.password);
const nuevo = await sesion(f.usuarios.ajeno, f.password);
const supervisorAnterior = await sesion(f.usuarios.supervisor, f.password);
const ejecucion = randomUUID();
const pruebas = [];
const casos = [];
const normal = handlerEnBanco(crearHandlerAccesoInversion);
const bandera = sql("select activo from crm.multiempresa_flags where nombre='inversiones_escritura'");
sql("update crm.multiempresa_flags set activo=true where nombre='inversiones_escritura'");
sql(`update public.perfiles set telefono='999450004' where id=${q(f.usuarios.ajeno.id)} and telefono is null;`);
const firmaSolicitud = id => sql(`select jsonb_build_object('datos',datos,'hash',hash_payload,'contexto',auth_contexto,'claim',auth_claim_id)::text
  from crm.inversion_solicitudes where id=${q(id)}`);
const saga = persona => sql(`select coalesce((select to_jsonb(m)::text from crm.multiempresa_idempotencia m where clave=${q(`auth_persona:${persona}`)}),'null')`);
const revisar = (c, token = nuevo, cambios = {}) => rpc('revisar_solicitud_inversion_fn', {
  p_solicitud: c.solicitud, p_responsable_revisado: f.usuarios.ajeno.id,
  p_revision_esperada: 0, p_motivo: 'Revisión ficticia tras cambio de equipo comercial', ...cambios,
}, token);
try {
  for (const corte of ['sin_auth', 'auth', 'registrar_auth', 'crear_perfil', 'enlazar']) {
    const c = await prepararPersonaPortal({ vendedor: f.usuarios.vendedor.id, token: t, etiqueta: `revision_${corte}` });
    casos.push(c);
    guardar(`revision-responsable-${ejecucion}.json`, casos);
    ok(await rpc('preparar_inversion_fn', { p_clave: c.solicitud, p_datos: c.datos }, t), 'Preparar revisión');
    let recuperacion;
    if (corte !== 'sin_auth') {
      let perdido = false;
      const conCorte = handlerEnBanco(crearHandlerAccesoInversion, async (url, opciones) => {
        const r = await fetch(url, opciones);
        const paso = url.endsWith('/rest/v1/rpc/acceso_inversion_fn') ? JSON.parse(opciones.body).p_paso : null;
        if (!perdido && r.ok && ((corte === 'auth' && url.endsWith('/auth/v1/admin/users')) || paso === corte)) {
          await r.clone().json(); perdido = true;
          throw new TypeError('Respuesta real perdida antes de la reasignación');
        }
        return r;
      });
      const r = await llamarHandler(conCorte, c.solicitud, t);
      assert.equal(r.status, 503);
      assert.equal(perdido, true);
      recuperacion = r.data.token;
      assert.match(recuperacion, /^[a-f0-9]{48}$/);
    }
    const contenidoOriginal = firmaSolicitud(c.solicitud);
    const sagaOriginal = saga(c.persona);
    const perfilOriginal = estadoAcceso(c.solicitud).auth;
    const datosPerfil = perfilOriginal ? sql(`select (to_jsonb(p)-'asesor_perfil_id'-'actualizado_en')::text from public.perfiles p where id=${q(perfilOriginal)}`) : '';
    ok(await rpc('reasignar_responsable_relacion_fn', { p_inversionista: c.persona,
      p_nuevo_responsable: f.usuarios.ajeno.id, p_motivo: 'Reasignación ficticia entre los pasos de acceso Avance' }, gerente), 'Reasignar por puerta canónica');
    assert.equal((await revisar(c, t)).data.code, '42501');
    assert.equal((await revisar(c, supervisorAnterior)).data.code, '42501');
    assert.equal((await llamarHandler(normal, c.solicitud, t, recuperacion)).status, 403);
    assert.equal((await rpc('confirmar_inversion_fn', { p_solicitud: c.solicitud }, nuevo)).data.code, 'P0409');
    assert.equal((await llamarHandler(normal, c.solicitud, nuevo, recuperacion)).status, 409);
    const lectura = ok(await rpc('preparar_inversion_fn', { p_clave: c.solicitud, p_datos: c.datos }, nuevo), 'Nuevo equipo recupera la solicitud existente');
    assert.equal(lectura.requiere_revision_responsable, true);
    assert.equal(lectura.revision_responsable, 0);
    assert.equal(lectura.responsable_actual_id, f.usuarios.ajeno.id);
    assert.equal((await revisar(c, nuevo, { p_responsable_revisado: f.usuarios.vendedor.id })).data.code, '40001');
    assert.equal((await revisar(c, nuevo, { p_motivo: `Motivo inválido ${c.documento}` })).data.code, '22023');
    assert.equal(sql(`select count(*) from crm.inversion_solicitud_revisiones where solicitud_id=${q(c.solicitud)}`), '0');
    const respuestas = await Promise.all([revisar(c), revisar(c)]);
    for (const r of respuestas) {
      const res = ok(r, 'Revisión concurrente/repetida');
      assert.equal(res.revision_responsable, 1);
      assert.equal(res.requiere_revision_responsable, false);
    }
    assert.equal(respuestas.filter(r => r.data.reintento === false).length, 1);
    assert.equal(respuestas.filter(r => r.data.reintento === true).length, 1);
    assert.equal(sql(`select count(*) from crm.inversion_solicitud_revisiones where solicitud_id=${q(c.solicitud)}`), '1');
    assert.equal(firmaSolicitud(c.solicitud), contenidoOriginal, 'La revisión alteró el contenido/hash/contexto/claim');
    assert.equal(saga(c.persona), sagaOriginal, 'La revisión alteró el token, versión o lease de Auth');
    assert.equal((await revisar(c, nuevo, { p_motivo: 'Otro motivo con la versión anterior' })).data.code, '40001');
    if (datosPerfil) assert.equal(sql(`select (to_jsonb(p)-'asesor_perfil_id'-'actualizado_en')::text from public.perfiles p where id=${q(perfilOriginal)}`), datosPerfil,
      'La alineación del asesor modificó otros campos del perfil');
    if (!['sin_auth','enlazar'].includes(corte)) {
      assert.equal((await llamarHandler(normal, c.solicitud, nuevo)).status, 409, 'La revisión no autoriza robar el lease sin token');
    }
    const acceso = ok(await llamarHandler(normal, c.solicitud, nuevo, recuperacion), 'Reanudar desde el equipo actual');
    c.perfil = acceso.perfil_id;
    assert.equal(sql(`select asesor_perfil_id from public.perfiles where id=${q(c.perfil)}`), f.usuarios.ajeno.id);
    c.resultado = ok(await rpc('confirmar_inversion_fn', { p_solicitud: c.solicitud }, nuevo), 'Confirmar con el responsable revisado');
    assert.equal(sql(`select analista_cierre_id from public.contratos where id=${q(c.resultado.fuente.id)}`), f.usuarios.ajeno.id);
    assert.equal(sql(`select count(*) from auth.users where lower(email)=${q(c.datos.alta_portal.correo)}`), '1');
    assert.equal(sql(`select count(*) from crm.leads where inversionista_id=${q(c.persona)}`), '1');
    assert.equal(sql(`select count(*) from crm.inversiones where inversionista_id=${q(c.persona)} and contrato_id is not null`), '1');
    assert.equal((await revisar(c, nuevo, { p_revision_esperada: 1 })).data.code, 'P0409', 'Una inversión confirmada no se reatribuye por revisión');
    // La relación puede cambiar después; el replay devuelve la fuente original.
    ok(await rpc('reasignar_responsable_relacion_fn', { p_inversionista: c.persona,
      p_nuevo_responsable: f.usuarios.vendedor.id, p_motivo: 'Segundo cambio ficticio después de confirmar la inversión' }, gerente), 'Cambiar relación después de confirmar');
    const replay = ok(await rpc('confirmar_inversion_fn', { p_solicitud: c.solicitud }, t), 'Repetir desde el ámbito actual');
    assert.equal(replay.inversion_id, c.resultado.inversion_id);
    assert.equal(sql(`select analista_cierre_id from public.contratos where id=${q(c.resultado.fuente.id)}`), f.usuarios.ajeno.id);
    assert.equal((await rpc('confirmar_inversion_fn', { p_solicitud: c.solicitud }, nuevo)).data.code, '42501');
    pruebas.push({ corte, equipoAnteriorRechazado: true, revisionUnica: true,
      datosHashYAuthIntactos: true, perfilAlineado: true, recuperadoSinDuplicados: true,
      atribucionConfirmadaConservadaTrasOtraReasignacion: true });
    guardar(`revision-responsable-${ejecucion}.json`, casos);
    console.log(`Conforme: cambio de equipo en ${corte}, revisión y recuperación de la misma solicitud.`);
  }
  writeFileSync(new URL(`../evidencia-f4/revision-responsable-${ejecucion}.json`, import.meta.url), JSON.stringify({
    entorno, ejecucion, terminadoEn: new Date().toISOString(), pruebas,
    limite: 'Cubre reasignación con documento estable. Fusión, corrección de documento y PDF siguen pendientes.',
  }, null, 2) + '\n');
  console.log('Revisión F4: cinco cortes, ámbito actual, historial y atribución conservados.');
} finally {
  sql(`update crm.multiempresa_flags set activo=${bandera === 't'} where nombre='inversiones_escritura'`);
}
