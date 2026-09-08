import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { writeFileSync } from 'node:fs';
import { crearHandlerAccesoInversion } from '../../../../_supabase_functions/functions/crm-inversion-portal/handler.mjs';
import { sql, literal as q, leer, guardar, sesion, rpc, http, handlerEnBanco } from './banco-local.mjs';
import { comprobar as ok, contadoresPortal, prepararPersonaPortal, llamarHandler, estadoAcceso } from './portal-fixture.mjs';

const f = leer('fixtures.json');
const vendedor = f.usuarios.vendedor.id;
const t = await sesion(f.usuarios.vendedor, f.password);
const supervisor = await sesion(f.usuarios.supervisor, f.password);
const ajeno = await sesion(f.usuarios.ajeno, f.password);
const ejecucion = randomUUID();
const pruebas = [];
const registros = [];
const normal = handlerEnBanco(crearHandlerAccesoInversion);
const bien = nombre => { pruebas.push({ nombre, conforme: true }); console.log(`Conforme: ${nombre}`); };
const preparar = c => rpc('preparar_inversion_fn', { p_clave: c.solicitud, p_datos: c.datos }, supervisor);
const nuevo = async (etiqueta, correo) => {
  const c = await prepararPersonaPortal({ vendedor, token: t, etiqueta, correo });
  registros.push(c);
  guardar(`portal-nuevo-${ejecucion}.json`, registros);
  return c;
};
const flagAntes = sql("select activo from crm.multiempresa_flags where nombre='inversiones_escritura'");
sql("update crm.multiempresa_flags set activo=true where nombre='inversiones_escritura'");
// Datos ficticios del firmante para los snapshots contractuales del ensayo.
sql(`update public.perfiles set telefono='999450002' where id=${q(f.usuarios.supervisor.id)} and telefono is null;`);
try {
  const invalida = await nuevo('validacion');
  const antes = contadoresPortal();
  for (const alta of [null, { ...invalida.datos.alta_portal, domicilio: 'PENDIENTE' },
    { ...invalida.datos.alta_portal, asesor_id: f.usuarios.supervisor.id },
    { ...invalida.datos.alta_portal, password: 'NO-DEBE-GUARDARSE' }]) {
    const mal = await rpc('preparar_inversion_fn', { p_clave: invalida.solicitud,
      p_datos: { ...invalida.datos, alta_portal: alta } }, supervisor);
    assert.equal(mal.ok, false);
    assert.equal(mal.data.code, '22023');
  }
  assert.deepEqual(contadoresPortal(), antes);
  assert.equal(sql(`select count(*) from crm.inversion_solicitudes where id=${q(invalida.solicitud)}`), '0');
  bien('Datos legales inválidos y campos ajenos rechazados antes de Auth y de la solicitud');

  for (const corte of ['auth', 'registrar_auth', 'crear_perfil', 'enlazar']) {
    const c = await nuevo(corte);
    ok(await preparar(c), 'Preparar acceso');
    const previos = contadoresPortal();
    let interceptado = false;
    const conCorte = handlerEnBanco(crearHandlerAccesoInversion, async (url, opciones) => {
      const r = await fetch(url, opciones);
      const paso = url.endsWith('/rest/v1/rpc/acceso_inversion_fn') ? JSON.parse(opciones.body).p_paso : null;
      if (!interceptado && r.ok && ((corte === 'auth' && url.endsWith('/auth/v1/admin/users')) || paso === corte)) {
        await r.clone().json(); // El servicio respondió tras confirmar su escritura real.
        interceptado = true;
        throw new TypeError('Pérdida de respuesta real provocada por el oráculo');
      }
      return r;
    });
    const perdida = await llamarHandler(conCorte, c.solicitud, supervisor);
    assert.equal(interceptado, true);
    assert.equal(perdida.status, 503);
    assert.match(perdida.data.token ?? '', /^[a-f0-9]{48}$/);
    const parcial = estadoAcceso(c.solicitud);
    assert.equal(parcial.estado, 'preparada');
    assert.equal(parcial.inversion, null);
    assert.equal(parcial.saga, { auth: 'reclamado', registrar_auth: 'auth_creado', crear_perfil: 'perfil_creado', enlazar: 'enlazado' }[corte]);
    assert.equal(parcial.perfilesCreados, ['crear_perfil', 'enlazar'].includes(corte) ? 1 : 0);
    assert.equal(Boolean(parcial.perfil), corte === 'enlazar');
    assert.equal(contadoresPortal().auth, previos.auth + 1);
    assert.equal(contadoresPortal().contratos, previos.contratos);
    const recuperada = ok(await llamarHandler(normal, c.solicitud, supervisor, perdida.data.token), `Recuperar corte ${corte}`);
    c.perfil = recuperada.perfil_id;
    const propietario = JSON.parse(sql(`select jsonb_build_object('responsable',i.responsable_relacion_id,
      'asesor',p.asesor_perfil_id,'creador',p.creado_por,'documento',p.dni,'cambiarClave',p.debe_cambiar_password)
      from crm.inversionistas i join public.perfiles p on p.id=i.perfil_id where i.id=${q(c.persona)}`));
    assert.deepEqual(propietario, { responsable: vendedor, asesor: vendedor, creador: f.usuarios.supervisor.id,
      documento: c.documento, cambiarClave: true });
    const resultado = ok(await rpc('confirmar_inversion_fn', { p_solicitud: c.solicitud }, supervisor), 'Confirmar Qorilazo a Avance');
    c.resultado = resultado;
    const cuenta = await sesion({ id: c.perfil, email: c.datos.alta_portal.correo }, c.documento);
    assert.deepEqual(ok(await http(`/rest/v1/contratos?id=eq.${resultado.fuente.id}&select=id,cliente_id`, {
      method: 'GET', token: cuenta,
    }), 'Portal nuevo propio'), [{ id: resultado.fuente.id, cliente_id: c.perfil }]);
    assert.deepEqual(ok(await http(`/rest/v1/contratos?id=eq.${resultado.fuente.id}&select=id`, {
      method: 'GET', token: ajeno,
    }), 'Portal ajeno'), []);
    const repetida = ok(await llamarHandler(normal, c.solicitud, supervisor), 'Repetir acceso concluido');
    assert.equal(repetida.perfil_id, c.perfil);
    assert.equal(ok(await rpc('confirmar_inversion_fn', { p_solicitud: c.solicitud }, supervisor), 'Repetir confirmación').inversion_id, resultado.inversion_id);
    const finales = contadoresPortal();
    assert.equal(finales.auth, previos.auth + 1);
    assert.equal(finales.perfiles, previos.perfiles + 1);
    assert.equal(finales.personas, previos.personas);
    assert.equal(finales.leads, previos.leads);
    assert.equal(finales.inversiones, previos.inversiones + 1);
    assert.equal(finales.contratos, previos.contratos + 1);
    assert.equal(finales.cuotas, previos.cuotas + 13);
    assert.equal(estadoAcceso(c.solicitud).saga, 'enlazado');
    bien(`Qorilazo→Avance recuperado tras ${corte}: un acceso, un contrato, responsable conservado y Portal autorizado`);
    guardar(`portal-nuevo-${ejecucion}.json`, registros);
  }

  const carrera = await nuevo('simultaneas');
  ok(await preparar(carrera), 'Preparar concurrencia Auth');
  const previos = contadoresPortal();
  let liberar;
  const espera = new Promise(resolve => { liberar = resolve; });
  let avisar;
  const authCreado = new Promise(resolve => { avisar = resolve; });
  const retenida = handlerEnBanco(crearHandlerAccesoInversion, async (url, opciones) => {
    const r = await fetch(url, opciones);
    if (url.endsWith('/auth/v1/admin/users') && r.ok) { avisar(); await espera; }
    return r;
  });
  const primera = llamarHandler(retenida, carrera.solicitud, supervisor);
  let limite;
  try {
    await Promise.race([authCreado, primera.then(r => { throw new Error(`Primera solicitud terminó antes de crear Auth: ${r.status} ${r.data?.error ?? ''}`); }),
      new Promise((_, reject) => { limite = setTimeout(() => reject(new Error('No se observó Auth en 30 segundos')), 30_000); limite.unref(); })]);
    const segunda = await llamarHandler(normal, carrera.solicitud, supervisor);
    assert.equal(segunda.status, 409);
    assert.equal(contadoresPortal().auth, previos.auth + 1);
    assert.equal(contadoresPortal().perfiles, previos.perfiles);
  } finally { clearTimeout(limite); liberar(); }
  ok(await primera, 'Primera solicitud termina');
  assert.equal(contadoresPortal().auth, previos.auth + 1);
  assert.equal(contadoresPortal().perfiles, previos.perfiles + 1);
  bien('Dos ejecuciones simultáneas: el lease protege el alta y solo existe un Auth y un perfil');

  const colision = await nuevo('correo_ocupado', f.usuarios.cliente.email);
  ok(await preparar(colision), 'Preparar correo ocupado');
  const previoColision = contadoresPortal();
  const ocupada = await llamarHandler(normal, colision.solicitud, supervisor);
  assert.equal(ocupada.status, 409);
  assert.match(ocupada.data.error, /otro acceso/);
  assert.deepEqual(contadoresPortal(), previoColision);
  assert.equal(estadoAcceso(colision.solicitud).perfil, null);
  bien('Un correo de otro Auth no se adopta ni enlaza a la persona');

  const seguridad = await nuevo('permisos');
  ok(await preparar(seguridad), 'Preparar controles Auth');
  const sinAmbito = await llamarHandler(normal, seguridad.solicitud, ajeno);
  assert.equal(sinAmbito.status, 403);
  const claim = ok(await rpc('acceso_inversion_fn', { p_solicitud: seguridad.solicitud, p_paso: 'reclamar', p_payload: {} }, supervisor), 'Claim autorizado');
  const sinProcedencia = await rpc('acceso_inversion_fn', { p_solicitud: seguridad.solicitud, p_paso: 'registrar_auth',
    p_payload: { token: claim.token, version: claim.version, auth_user_id: f.usuarios.cliente.id } }, supervisor);
  assert.equal(sinProcedencia.ok, false);
  assert.equal(sinProcedencia.data.code, 'P0409');
  const falsificado = await rpc('acceso_inversion_fn', { p_solicitud: seguridad.solicitud, p_paso: 'crear_perfil',
    p_payload: { token: claim.token, version: claim.version, perfil_id: f.usuarios.cliente.id } }, supervisor);
  assert.equal(falsificado.data.code, '22023');
  const anon = await rpc('acceso_inversion_fn', { p_solicitud: seguridad.solicitud, p_paso: 'reclamar', p_payload: {} });
  assert.equal(anon.ok, false);
  const servicio = await http('/rest/v1/rpc/acceso_inversion_fn', { admin: true,
    headers: { 'Accept-Profile': 'crm', 'Content-Profile': 'crm' },
    body: { p_solicitud: seguridad.solicitud, p_paso: 'reclamar', p_payload: {} } });
  assert.equal(servicio.ok, false);
  ok(await llamarHandler(normal, seguridad.solicitud, supervisor, claim.token), 'Completar tras intentos rechazados');
  assert.equal(sql(`select count(*) from public.audit_log where tabla='crm.inversion_solicitudes'
    and jsonb_typeof(data_despues->'auth_contexto')='object'`), '0');
  bien('Ámbito, actor real, procedencia de Auth y columnas de auditoría verificados');
  writeFileSync(new URL(`../evidencia-f4/portal-nuevo-${ejecucion}.json`, import.meta.url), JSON.stringify({
    entorno: 'avancecorp-f4-bank', ejecucion, terminadoEn: new Date().toISOString(), pruebas,
    transporte: 'Handler de producción con Auth, PostgREST y Portal locales reales; pérdida deliberada de respuestas ya confirmadas',
    pendientes: ['Reanudación sin token después del lease', 'Cambio de responsable/documento/veto entre pasos', 'Fusión', 'Generación y recuperación PDF'],
  }, null, 2) + '\n');
  console.log(`Acceso nuevo F4: ${pruebas.length} grupos de comprobaciones conformes.`);
} finally {
  sql(`update crm.multiempresa_flags set activo=${flagAntes === 't'} where nombre='inversiones_escritura'`);
}
