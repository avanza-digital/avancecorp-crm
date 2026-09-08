import { entorno } from './banco-local.mjs';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { writeFileSync } from 'node:fs';
import { crearHandlerAccesoInversion } from '../../../../_supabase_functions/functions/crm-inversion-portal/handler.mjs';
import { sql, literal as q, leer, guardar, sesion, rpc, handlerEnBanco } from './banco-local.mjs';
import { comprobar as ok, prepararPersonaPortal, llamarHandler, estadoAcceso } from './portal-fixture.mjs';
import { retener } from './candados-prueba.mjs';

const f = leer('fixtures.json');
const t = await sesion(f.usuarios.vendedor, f.password);
const gerente = await sesion(f.usuarios.gerencia, f.password);
const b = await sesion(f.usuarios.ajeno, f.password);
const tercero = await sesion(f.usuarios.supervisor_ajeno, f.password);
const ejecucion = randomUUID();
assert.equal(sql("select activo from crm.multiempresa_flags where nombre='inversiones_escritura'"), 't');
const c = await prepararPersonaPortal({ vendedor: f.usuarios.vendedor.id, token: t, etiqueta: 'revision_controles' });
guardar(`revision-controles-${ejecucion}.json`, c);
ok(await rpc('preparar_inversion_fn', { p_clave: c.solicitud, p_datos: c.datos }, t), 'Preparar controles');
let perdido = false;
const corte = handlerEnBanco(crearHandlerAccesoInversion, async (url, opciones) => {
  const r = await fetch(url, opciones);
  if (!perdido && r.ok && url.endsWith('/rest/v1/rpc/acceso_inversion_fn') && JSON.parse(opciones.body).p_paso === 'crear_perfil') {
    await r.clone().json(); perdido = true;
    throw new TypeError('Perfil confirmado cuya respuesta se perdió');
  }
  return r;
});
const perdida = await llamarHandler(corte, c.solicitud, t);
assert.equal(perdida.status, 503);
assert.equal(perdido, true);
const estado = estadoAcceso(c.solicitud);
assert.equal(estado.saga, 'perfil_creado');
assert.equal(estado.perfil, null);
c.perfil = estado.auth;
const reasignar = (id, motivo) => rpc('reasignar_responsable_relacion_fn', {
  p_inversionista: c.persona, p_nuevo_responsable: id, p_motivo: motivo,
}, gerente);
const revisar = (id, version, token) => rpc('revisar_solicitud_inversion_fn', {
  p_solicitud: c.solicitud, p_responsable_revisado: id, p_revision_esperada: version,
  p_motivo: 'Revisión ficticia del responsable vigente y su recuperación',
}, token);
const huella = () => sql(`select md5((to_jsonb(s)-'actualizado_en')::text) from crm.inversion_solicitudes s where id=${q(c.solicitud)}`);
const huellaSaga = () => sql(`select md5(to_jsonb(m)::text) from crm.multiempresa_idempotencia m where clave=${q(`auth_persona:${c.persona}`)}`);
const liberar = await retener(`select 1 from public.perfiles where id=${q(c.perfil)} for update`);
try {
  ok(await reasignar(f.usuarios.ajeno.id, 'Cambio ficticio mientras otra sesión tiene la ficha parcial'), 'Reasignar identidad sin perfil enlazado');
  const antes = huella();
  const antesSaga = huellaSaga();
  const bloqueada = await revisar(f.usuarios.ajeno.id, 0, b);
  assert.equal(bloqueada.ok, false);
  assert.equal(bloqueada.data.code, '40001');
  assert.equal(huella(), antes);
  assert.equal(huellaSaga(), antesSaga);
  assert.equal(sql(`select count(*) from crm.inversion_solicitud_revisiones where solicitud_id=${q(c.solicitud)}`), '0');
} finally { await liberar(); }
ok(await revisar(f.usuarios.ajeno.id, 0, b), 'Revisar después de liberar ficha');
assert.equal(sql(`select asesor_perfil_id from public.perfiles where id=${q(c.perfil)}`), f.usuarios.ajeno.id);
console.log('Conforme: bloqueo real de perfil revierte la revisión entera y permite repetirla.');

// Un GUC adivinable no identifica por sí solo a una revisión autorizada.
// Reusar su id en otra transacción falla incluso bajo el ejecutor postgres.
const claims = JSON.stringify({ sub: f.usuarios.ajeno.id, role: 'authenticated' });
const configurar = `select set_config('request.jwt.claims',${q(claims)},true);
  select set_config('crm.f4_revision_solicitud',${q(c.solicitud)},true);`;
const pruebaTransaccion = sql(`begin; ${configurar}
  select private.f4_alineacion_perfil_permitida(${q(c.perfil)},${q(f.usuarios.ajeno.id)}); rollback;`).split('\n').at(-1);
assert.equal(pruebaTransaccion, 'f');
assert.equal(sql(`begin; ${configurar}
  select set_config('crm.f4_revision_solicitud','valor-invalido',true);
  select private.f4_alineacion_perfil_permitida(${q(c.perfil)},${q(f.usuarios.ajeno.id)}); rollback;`).split('\n').at(-1), 'f');
for (const rol of ['authenticated', 'postgres']) {
  const intento = sql(`begin; set local role ${rol}; ${configurar}
    update public.perfiles set asesor_perfil_id=${q(f.usuarios.vendedor.id)},activo=false,rol='admin',debe_cambiar_password=false
      where id=${q(c.perfil)};
    select jsonb_build_object('asesor',asesor_perfil_id,'activo',activo,'rol',rol,'cambiarClave',debe_cambiar_password)
      from public.perfiles where id=${q(c.perfil)};
    rollback;`).split('\n').at(-1);
  assert.deepEqual(JSON.parse(intento), { asesor: f.usuarios.ajeno.id, activo: true, rol: 'cliente', cambiarClave: true });
}
assert.throws(() => sql(`begin; update crm.inversion_solicitud_revisiones set motivo='Sobrescritura ficticia'
  where solicitud_id=${q(c.solicitud)}; rollback;`), /historial de una inversión no se modifica/);
assert.throws(() => sql(`begin; delete from crm.inversion_solicitud_revisiones where solicitud_id=${q(c.solicitud)}; rollback;`), /historial de una inversión no se modifica/);
console.log('Conforme: GUC reutilizado, cambios privilegiados y sobrescritura del historial rechazados.');

const hashAntes = sql(`select hash_payload from crm.inversion_solicitudes where id=${q(c.solicitud)}`);
const sagaAntes = huellaSaga();
ok(await reasignar(f.usuarios.supervisor_ajeno.id, 'Segundo cambio ficticio antes de confirmar la inversión'), 'Segundo cambio de relación');
ok(await revisar(f.usuarios.supervisor_ajeno.id, 1, tercero), 'Segunda revisión de la misma solicitud');
assert.equal(sql(`select hash_payload from crm.inversion_solicitudes where id=${q(c.solicitud)}`), hashAntes);
assert.equal(huellaSaga(), sagaAntes);
assert.equal(sql(`select count(*) from crm.inversion_solicitud_revisiones where solicitud_id=${q(c.solicitud)}`), '2');
assert.equal((await revisar(f.usuarios.supervisor_ajeno.id, 0, tercero)).data.code, '40001');
sql(`update public.perfiles set telefono='999450005' where id=${q(f.usuarios.supervisor_ajeno.id)} and telefono is null;`);
const acceso = ok(await llamarHandler(handlerEnBanco(crearHandlerAccesoInversion), c.solicitud, tercero, perdida.data.token), 'Tercer responsable retoma el mismo Auth');
assert.equal(acceso.perfil_id, c.perfil);
c.resultado = ok(await rpc('confirmar_inversion_fn', { p_solicitud: c.solicitud }, tercero), 'Confirmar después de dos revisiones');
assert.equal(sql(`select analista_cierre_id from public.contratos where id=${q(c.resultado.fuente.id)}`), f.usuarios.supervisor_ajeno.id);
assert.equal(sql(`select count(*) from auth.users where lower(email)=${q(c.datos.alta_portal.correo)}`), '1');
assert.equal(sql(`select count(*) from crm.inversiones where inversionista_id=${q(c.persona)} and contrato_id is not null`), '1');
guardar(`revision-controles-${ejecucion}.json`, c);
writeFileSync(new URL(`../evidencia-f4/revision-controles-${ejecucion}.json`, import.meta.url), JSON.stringify({
  entorno, ejecucion, terminadoEn: new Date().toISOString(),
  candadoRealDePerfil: true, revisionFallidaSinEfectos: true, reintentoTrasLiberar: true,
  gucReutilizadoNoAutorizaAlineacion: true, camposPrivilegiadosSiguenCongelados: true,
  revisionesNoSeEditanNiBorran: true, dosRevisionesConDatosHashYSagaIntactos: true,
  versionViejaRechazada: true, responsableRevisadoEnFuente: true, accesoEInversionUnicos: true,
}, null, 2) + '\n');
console.log('Conforme: dos revisiones conservan la intención original y confirman con el último responsable revisado.');
