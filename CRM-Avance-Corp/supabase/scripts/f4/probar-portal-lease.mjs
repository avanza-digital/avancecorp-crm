// Simula que se perdió la respuesta del primer reclamo, antes de conocer su token.
// Espera el lease REAL del servidor: no edita estados, versiones ni relojes SQL.
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { writeFileSync } from 'node:fs';
import { crearHandlerAccesoInversion } from '../../../../_supabase_functions/functions/crm-inversion-portal/handler.mjs';
import { sql, literal as q, leer, guardar, sesion, rpc, handlerEnBanco } from './banco-local.mjs';
import { comprobar as ok, prepararPersonaPortal, llamarHandler, estadoAcceso } from './portal-fixture.mjs';

const f = leer('fixtures.json');
const t = await sesion(f.usuarios.vendedor, f.password);
const ejecucion = randomUUID();
sql("update crm.multiempresa_flags set activo=true where nombre='inversiones_escritura'");
const c = await prepararPersonaPortal({ vendedor: f.usuarios.vendedor.id, token: t, etiqueta: 'lease_sin_token' });
guardar(`portal-lease-${ejecucion}.json`, c);
ok(await rpc('preparar_inversion_fn', { p_clave: c.solicitud, p_datos: c.datos }, t), 'Preparar prueba de lease');
let perdida = false;
const cortar = handlerEnBanco(crearHandlerAccesoInversion, async (url, opciones) => {
  const r = await fetch(url, opciones);
  if (!perdida && r.ok && url.endsWith('/rest/v1/rpc/acceso_inversion_fn')
    && JSON.parse(opciones.body).p_paso === 'reclamar') {
    await r.clone().json();
    perdida = true;
    throw new TypeError('Respuesta de reclamo perdida tras su commit');
  }
  return r;
});
const fallida = await llamarHandler(cortar, c.solicitud, t);
assert.equal(fallida.status, 503);
assert.equal(fallida.data.token, undefined);
assert.equal(perdida, true);
const inicial = estadoAcceso(c.solicitud);
assert.equal(inicial.saga, 'reclamado');
assert.equal(inicial.auth, null);
const limite = new Date(inicial.leaseHasta).getTime();
const normal = handlerEnBanco(crearHandlerAccesoInversion);
assert.equal((await llamarHandler(normal, c.solicitud, t)).status, 409);
console.log(`Lease real observado hasta ${new Date(limite).toISOString()}; reintento inmediato rechazado sin efectos.`);
while (Date.now() <= limite + 1000) {
  await new Promise(resolve => setTimeout(resolve, Math.min(30_000, limite + 1100 - Date.now())));
  const estado = estadoAcceso(c.solicitud);
  assert.equal(estado.saga, 'reclamado');
  assert.equal(estado.version, inicial.version);
  assert.equal(estado.leaseHasta, inicial.leaseHasta);
  console.log(`Lease sin alterar: quedan ${Math.max(0, Math.ceil((limite - Date.now()) / 1000))} segundos.`);
}
const acceso = ok(await llamarHandler(normal, c.solicitud, t), 'Recuperar después del lease real');
c.perfil = acceso.perfil_id;
c.resultado = ok(await rpc('confirmar_inversion_fn', { p_solicitud: c.solicitud }, t), 'Confirmar tras recuperación sin token');
assert.equal(sql(`select count(*) from auth.users where lower(email)=${q(c.datos.alta_portal.correo)}`), '1');
assert.equal(sql(`select count(*) from public.perfiles where id=${q(c.perfil)}`), '1');
assert.equal(sql(`select count(*) from crm.leads where inversionista_id=${q(c.persona)}`), '1');
assert.equal(sql(`select count(*) from crm.inversiones where inversionista_id=${q(c.persona)} and contrato_id is not null`), '1');
assert.equal(estadoAcceso(c.solicitud).saga, 'enlazado');
guardar(`portal-lease-${ejecucion}.json`, c);
writeFileSync(new URL(`../evidencia-f4/portal-lease-${ejecucion}.json`, import.meta.url), JSON.stringify({
  entorno: 'avancecorp-f4-bank', ejecucion, terminadoEn: new Date().toISOString(),
  perdidaDePrimerReclamoConfirmado: true, sinTokenRecuperadoPorElCliente: true,
  reintentoAntesDeLeaseRechazado: true, leaseOriginal: inicial.leaseHasta,
  leaseVersionYEstadoSinAlterarDuranteEspera: true, recuperadoSinTokenTrasVencimientoReal: true,
  authPerfilLeadYContratoUnicos: true, banderaInversiones: true,
}, null, 2) + '\n');
console.log('Conforme: respuesta inicial perdida, lease real respetado, recuperación sin token y contrato único.');
