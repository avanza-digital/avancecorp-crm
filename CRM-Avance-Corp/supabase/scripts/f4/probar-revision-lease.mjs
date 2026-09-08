// El equipo nuevo recupera un Auth ya creado sin recibir el token del anterior.
// Se espera el lease original; la revisión no lo cancela ni lo prolonga.
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { writeFileSync } from 'node:fs';
import { crearHandlerAccesoInversion } from '../../../../_supabase_functions/functions/crm-inversion-portal/handler.mjs';
import { sql, literal as q, leer, guardar, sesion, rpc, handlerEnBanco } from './banco-local.mjs';
import { comprobar as ok, prepararPersonaPortal, llamarHandler, estadoAcceso } from './portal-fixture.mjs';

const f = leer('fixtures.json');
const anterior = await sesion(f.usuarios.vendedor, f.password);
const gerente = await sesion(f.usuarios.gerencia, f.password);
const actual = await sesion(f.usuarios.ajeno, f.password);
const ejecucion = randomUUID();
sql("update crm.multiempresa_flags set activo=true where nombre='inversiones_escritura'");
const c = await prepararPersonaPortal({ vendedor: f.usuarios.vendedor.id, token: anterior, etiqueta: 'revision_lease' });
guardar(`revision-lease-${ejecucion}.json`, c);
ok(await rpc('preparar_inversion_fn', { p_clave: c.solicitud, p_datos: c.datos }, anterior), 'Preparar cambio sin token');
let perdida = false;
const conCorte = handlerEnBanco(crearHandlerAccesoInversion, async (url, opciones) => {
  const r = await fetch(url, opciones);
  if (!perdida && r.ok && url.endsWith('/auth/v1/admin/users')) {
    await r.clone().json(); perdida = true;
    throw new TypeError('Respuesta perdida después del alta real de Auth');
  }
  return r;
});
assert.equal((await llamarHandler(conCorte, c.solicitud, anterior)).status, 503);
assert.equal(perdida, true);
const inicial = estadoAcceso(c.solicitud);
assert.equal(sql(`select count(*) from auth.users where lower(email)=${q(c.datos.alta_portal.correo)}`), '1');
assert.equal(inicial.saga, 'reclamado');
ok(await rpc('reasignar_responsable_relacion_fn', { p_inversionista: c.persona,
  p_nuevo_responsable: f.usuarios.ajeno.id, p_motivo: 'Cambio ficticio de equipo sin entregar el token anterior' }, gerente), 'Reasignar');
ok(await rpc('revisar_solicitud_inversion_fn', { p_solicitud: c.solicitud,
  p_responsable_revisado: f.usuarios.ajeno.id, p_revision_esperada: 0,
  p_motivo: 'Equipo actual revisa y espera el plazo de recuperación original' }, actual), 'Revisar desde nuevo equipo');
const normal = handlerEnBanco(crearHandlerAccesoInversion);
assert.equal((await llamarHandler(normal, c.solicitud, actual)).status, 409);
assert.equal((await llamarHandler(normal, c.solicitud, anterior)).status, 403);
const limite = new Date(inicial.leaseHasta).getTime();
console.log(`Cambio de equipo real; Auth existente; lease original hasta ${new Date(limite).toISOString()}.`);
while (Date.now() <= limite + 1000) {
  const estado = estadoAcceso(c.solicitud);
  assert.equal(estado.saga, inicial.saga);
  assert.equal(estado.version, inicial.version);
  assert.equal(estado.leaseHasta, inicial.leaseHasta);
  await new Promise(resolve => setTimeout(resolve, Math.min(30_000, limite + 1100 - Date.now())));
  console.log(`Lease del equipo anterior respetado: ${Math.max(0, Math.ceil((limite - Date.now()) / 1000))} segundos restantes.`);
}
c.perfil = ok(await llamarHandler(normal, c.solicitud, actual), 'Recuperar como responsable actual sin token').perfil_id;
c.resultado = ok(await rpc('confirmar_inversion_fn', { p_solicitud: c.solicitud }, actual), 'Confirmar inversión recuperada');
assert.equal(sql(`select asesor_perfil_id from public.perfiles where id=${q(c.perfil)}`), f.usuarios.ajeno.id);
assert.equal(sql(`select analista_cierre_id from public.contratos where id=${q(c.resultado.fuente.id)}`), f.usuarios.ajeno.id);
assert.equal(sql(`select count(*) from auth.users where lower(email)=${q(c.datos.alta_portal.correo)}`), '1');
assert.equal(sql(`select count(*) from crm.inversiones where inversionista_id=${q(c.persona)} and contrato_id is not null`), '1');
assert.equal((await rpc('confirmar_inversion_fn', { p_solicitud: c.solicitud }, anterior)).data.code, '42501');
guardar(`revision-lease-${ejecucion}.json`, c);
writeFileSync(new URL(`../evidencia-f4/revision-lease-${ejecucion}.json`, import.meta.url), JSON.stringify({
  entorno: 'avancecorp-f4-bank', ejecucion, terminadoEn: new Date().toISOString(),
  authCreadoAntesDeCambiarEquipo: true, sinTokenDelEquipoAnterior: true,
  leaseOriginal: inicial.leaseHasta, versionEstadoYLeaseSinAlterarPorRevision: true,
  equipoAnteriorRechazado: true, nuevoEquipoRecuperaTrasVencimientoReal: true,
  authPerfilYContratoUnicos: true, perfilYAtribucionConResponsableRevisado: true,
}, null, 2) + '\n');
console.log('Conforme: el equipo actual recuperó el mismo Auth y la inversión tras el lease real, sin token anterior.');
