// Comprueba el entrypoint Deno servido por el CLI, además del handler ensayado.
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { writeFileSync } from 'node:fs';
import { sql, literal as q, leer, guardar, sesion, rpc, http } from './banco-local.mjs';
import { comprobar as ok, prepararPersonaPortal, estadoAcceso } from './portal-fixture.mjs';

const f = leer('fixtures.json');
const vendedor = await sesion(f.usuarios.vendedor, f.password);
const gerente = await sesion(f.usuarios.gerencia, f.password);
const ajeno = await sesion(f.usuarios.ajeno, f.password);
const ejecucion = randomUUID();
assert.equal(sql("select activo from crm.multiempresa_flags where nombre='inversiones_escritura'"), 't',
  'Activa el escritor solo en el banco antes de esta prueba');
sql(`update public.perfiles set telefono='999450003' where id=${q(f.usuarios.gerencia.id)} and telefono is null;`);
const c = await prepararPersonaPortal({ vendedor: f.usuarios.vendedor.id, token: vendedor, etiqueta: 'deno_http' });
guardar(`portal-edge-${ejecucion}.json`, c);
ok(await rpc('preparar_inversion_fn', { p_clave: c.solicitud, p_datos: c.datos }, gerente), 'Preparar con Gerencia');
const llamar = (token, body = { solicitud_id: c.solicitud }) => http('/functions/v1/crm-inversion-portal', { token, body });
assert.equal((await llamar(gerente, { solicitud_id: c.solicitud, asesor_id: f.usuarios.gerencia.id })).status, 400);
assert.equal((await llamar(ajeno)).status, 403);
assert.equal((await llamar()).ok, false);
assert.equal(estadoAcceso(c.solicitud).saga, null);
const r = ok(await llamar(gerente), 'Crear Portal a través del entrypoint Deno');
c.perfil = r.perfil_id;
c.resultado = ok(await rpc('confirmar_inversion_fn', { p_solicitud: c.solicitud }, gerente), 'Confirmar como Gerencia');
assert.equal(sql(`select asesor_perfil_id from public.perfiles where id=${q(c.perfil)}`), f.usuarios.vendedor.id);
assert.equal(sql(`select creado_por from public.perfiles where id=${q(c.perfil)}`), f.usuarios.gerencia.id);
assert.equal(sql(`select analista_cierre_id from public.contratos where id=${q(c.resultado.fuente.id)}`), f.usuarios.vendedor.id);
assert.equal(ok(await llamar(gerente), 'Reintento HTTP').perfil_id, c.perfil);
const propio = await sesion({ id: c.perfil, email: c.datos.alta_portal.correo }, c.documento);
assert.deepEqual(ok(await http(`/rest/v1/contratos?id=eq.${c.resultado.fuente.id}&select=id`, {
  token: propio, method: 'GET',
}), 'Portal propio'), [{ id: c.resultado.fuente.id }]);
assert.equal(sql(`select count(*) from auth.users where lower(email)=${q(c.datos.alta_portal.correo)}`), '1');
assert.equal(sql(`select count(*) from crm.inversiones where inversionista_id=${q(c.persona)} and contrato_id is not null`), '1');
guardar(`portal-edge-${ejecucion}.json`, c);
writeFileSync(new URL(`../evidencia-f4/portal-edge-${ejecucion}.json`, import.meta.url), JSON.stringify({
  entorno: 'avancecorp-f4-bank', ejecucion, terminadoEn: new Date().toISOString(),
  entrypointDenoPorHTTPReal: true, autorizacionReal: true, camposDeAutoridadNoAdmitidos: true,
  gerenciaConservaResponsableDeLaPersona: true, accesoContratoYReintentoUnicos: true, portalPropio: true,
  limite: 'No prueba UI F5 ni el procesamiento del PDF ni publicación en producción.',
}, null, 2) + '\n');
console.log('Edge Portal local: HTTP real, Gerencia conserva al responsable, rechazos de acceso, contrato único y Portal propio conformes.');
