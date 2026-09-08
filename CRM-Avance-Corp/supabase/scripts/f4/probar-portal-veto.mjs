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
const ejecucion = randomUUID();
const pruebas = [];
const casos = [];
const normal = handlerEnBanco(crearHandlerAccesoInversion);
assert.equal(sql("select activo from crm.multiempresa_flags where nombre='inversiones_escritura'"), 't');
for (const corte of ['auth', 'registrar_auth', 'crear_perfil', 'enlazar']) {
  const c = await prepararPersonaPortal({ vendedor: f.usuarios.vendedor.id, token: t, etiqueta: `veto_${corte}` });
  casos.push(c);
  guardar(`portal-veto-${ejecucion}.json`, casos);
  ok(await rpc('preparar_inversion_fn', { p_clave: c.solicitud, p_datos: c.datos }, t), 'Preparar veto dinámico');
  let aplicado = false;
  const intercalar = handlerEnBanco(crearHandlerAccesoInversion, async (url, opciones) => {
    const r = await fetch(url, opciones);
    const paso = url.endsWith('/rest/v1/rpc/acceso_inversion_fn') ? JSON.parse(opciones.body).p_paso : null;
    if (!aplicado && r.ok && ((corte === 'auth' && url.endsWith('/auth/v1/admin/users')) || paso === corte)) {
      await r.clone().json();
      ok(await rpc('marcar_no_contactar', { p_lead_id: c.lead, p_motivo: 'Veto ficticio entre pasos del ensayo F4' }, gerente), 'Marcar por puerta vigente');
      aplicado = true;
    }
    return r;
  });
  try {
    const r = await llamarHandler(intercalar, c.solicitud, t);
    assert.equal(aplicado, true);
    assert.equal(r.status, corte === 'enlazar' ? 200 : 409);
    const detenido = estadoAcceso(c.solicitud);
    assert.equal(detenido.estado, 'preparada');
    assert.equal(detenido.inversion, null);
    const confirmarVetada = await rpc('confirmar_inversion_fn', { p_solicitud: c.solicitud }, t);
    assert.equal(confirmarVetada.ok, false);
    assert.equal(confirmarVetada.data.code, 'P0429');
    assert.equal((await llamarHandler(normal, c.solicitud, t, r.data.token)).status, 409);
    assert.equal(sql(`select count(*) from crm.inversiones where inversionista_id=${q(c.persona)} and contrato_id is not null`), '0');
    const vendedorIntentaLevantar = await rpc('levantar_no_contactar', {
      p_lead_id: c.lead, p_motivo: 'Intento ficticio de levantar sin Gerencia',
    }, t);
    assert.equal(vendedorIntentaLevantar.data.code, '42501');
    ok(await rpc('levantar_no_contactar', { p_lead_id: c.lead, p_motivo: 'Gerencia levanta el veto ficticio tras comprobar el bloqueo' }, gerente), 'Levantar con Gerencia');
    const acceso = ok(await llamarHandler(normal, c.solicitud, t, r.data.token), 'Reanudar tras levantamiento autorizado');
    c.perfil = acceso.perfil_id;
    c.resultado = ok(await rpc('confirmar_inversion_fn', { p_solicitud: c.solicitud }, t), 'Confirmar tras levantar veto');
    assert.equal(sql(`select count(*) from auth.users where lower(email)=${q(c.datos.alta_portal.correo)}`), '1');
    assert.equal(sql(`select count(*) from crm.inversiones where inversionista_id=${q(c.persona)} and contrato_id is not null`), '1');
    assert.equal(estadoAcceso(c.solicitud).saga, 'enlazado');
    pruebas.push({ corte, vetoPorRpcVigente: true, inversionBloqueada: true,
      soloGerenciaLevanta: true, recuperadaSinDuplicados: true });
    guardar(`portal-veto-${ejecucion}.json`, casos);
    console.log(`Conforme: veto después de ${corte}, bloqueo y recuperación autorizada sin duplicados.`);
  } finally {
    if (sql(`select no_contactar from crm.inversionistas where id=${q(c.persona)}`) === 't') {
      ok(await rpc('levantar_no_contactar', { p_lead_id: c.lead, p_motivo: 'Fin del ensayo ficticio de veto F4' }, gerente), 'Restituir persona ficticia');
    }
  }
}
writeFileSync(new URL(`../evidencia-f4/portal-veto-${ejecucion}.json`, import.meta.url), JSON.stringify({
  entorno, ejecucion, terminadoEn: new Date().toISOString(), pruebas,
  limite: 'Cubre No insistir entre pasos. Reasignación, cambio de documento, rol y fusión siguen pendientes.',
}, null, 2) + '\n');
console.log('Veto dinámico F4: cuatro cortes por puertas vigentes, bloqueos y recuperación comprobados.');
