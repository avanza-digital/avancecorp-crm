import { entorno } from './banco-local.mjs';
import assert from 'node:assert/strict';
import { createHash, randomUUID } from 'node:crypto';
import { writeFileSync } from 'node:fs';
import { crearHandlerAccesoInversion } from '../../../../_supabase_functions/functions/crm-inversion-portal/handler.mjs';
import { sql, literal as q, leer, guardar, sesion, rpc, http, handlerEnBanco } from './banco-local.mjs';
import { comprobar as ok, prepararPersonaPortal, llamarHandler } from './portal-fixture.mjs';
import { crearCanonica, fusionar, firmaIntencion, firmaSaga } from './fusion-fixture.mjs';

const f = leer('fixtures.json');
const t = await sesion(f.usuarios.vendedor, f.password);
const gerente = await sesion(f.usuarios.gerencia, f.password);
const nuevo = await sesion(f.usuarios.ajeno, f.password);
const normal = handlerEnBanco(crearHandlerAccesoInversion);
const ejecucion = randomUUID();
const pruebas = [];
const casos = [];
const bandera = sql("select activo from crm.multiempresa_flags where nombre='inversiones_escritura'");
const original = leer('functions-prod.json').find(x => x.schema === 'crm' && x.nombre === 'fusionar_inversionistas_fn');
assert(original);
const huellaFusion = createHash('md5').update(original.body).digest('hex');
assert.equal(sql("select md5(prosrc) from pg_proc where oid='crm.fusionar_inversionistas_fn(uuid,uuid,text,text)'::regprocedure"), huellaFusion);
const nuevaCanonica = (responsable = f.usuarios.ajeno.id, tipo = 'CE') => crearCanonica({
  gerente, responsable, creador: f.usuarios.gerencia.id, tipo,
});
const revisar = (c, responsable, revision, token) => rpc('revisar_solicitud_inversion_fn', {
  p_solicitud: c.solicitud, p_responsable_revisado: responsable, p_revision_esperada: revision,
  p_motivo: 'Revisión de responsable actual después de fusionar las fichas ficticias',
}, token);
const leerPreparada = (c, token) => rpc('preparar_inversion_fn', { p_clave: c.solicitud, p_datos: c.datos }, token);
const contenidoCierre = c => sql(`select md5((to_jsonb(ce)-'inversionista_id'-'actualizado_en')::text)
  from crm.cierres_externos ce where lead_id=${q(c.lead)} and es_cierre_inicial`);
const comprobarPrincipal = (c, resultado, persona) => {
  assert.equal(sql(`select inversionista_id from crm.inversiones where id=${q(resultado.inversion_id)}`), persona);
  assert.equal(sql(`select inversionista_id from crm.inversion_titulares where inversion_id=${q(resultado.inversion_id)} and rol='principal'`), persona);
  assert.equal(sql(`select count(*) from crm.leads where inversionista_id=${q(persona)}`), '1');
  assert.equal(sql(`select count(*) from crm.inversion_solicitudes where id=${q(c.solicitud)}`), '1');
  assert.equal(sql(`select inversionista_id from crm.inversion_solicitudes where id=${q(c.solicitud)}`), c.persona);
};

sql("update crm.multiempresa_flags set activo=true where nombre='inversiones_escritura'");
try {
  for (const corte of ['sin_auth', 'auth', 'crear_perfil', 'enlazar', 'confirmada']) {
    const c = await prepararPersonaPortal({ vendedor: f.usuarios.vendedor.id, token: t, etiqueta: `fusion_${corte}` });
    c.canonica = await nuevaCanonica();
    casos.push(c);
    guardar(`fusion-${ejecucion}.json`, casos);
    ok(await leerPreparada(c, t), 'Preparar en ficha original');
    const antecedente = contenidoCierre(c);
    if (corte === 'confirmada') {
      c.perfil = ok(await llamarHandler(normal, c.solicitud, t), 'Completar acceso antes de confirmar').perfil_id;
      c.resultado = ok(await rpc('confirmar_inversion_fn', { p_solicitud: c.solicitud }, t), 'Confirmar antes de fusionar');
    } else if (corte !== 'sin_auth') {
      let perdida = false;
      const conCorte = handlerEnBanco(crearHandlerAccesoInversion, async (url, opciones) => {
        const r = await fetch(url, opciones);
        const paso = url.endsWith('/rest/v1/rpc/acceso_inversion_fn') ? JSON.parse(opciones.body).p_paso : null;
        if (!perdida && r.ok && ((corte === 'auth' && url.endsWith('/auth/v1/admin/users')) || paso === corte)) {
          await r.clone().json(); perdida = true;
          throw new TypeError('Respuesta real perdida antes de solicitar fusión');
        }
        return r;
      });
      const r = await llamarHandler(conCorte, c.solicitud, t);
      assert.equal(r.status, 503);
      assert.equal(perdida, true);
      c.tokenSaga = r.data.token;
    }
    if (['auth','crear_perfil'].includes(corte)) {
      const intencionAntes = firmaIntencion(c);
      const sagaAntes = firmaSaga(c);
      const p = ok(await rpc('fusion_previsualizar_fn', { p_perdedora: c.persona, p_canonica: c.canonica.persona }, gerente), 'Previsualizar con Auth incompleto');
      assert.equal(p.viable, false);
      assert(p.bloqueos.some(b => /claim de Auth no terminal/.test(b)));
      const rechazo = await rpc('fusionar_inversionistas_fn', { p_perdedora: c.persona,
        p_canonica: c.canonica.persona, p_hash: p.hash, p_motivo: 'Ensayo ficticio con acceso aún pendiente' }, gerente);
      assert.equal(rechazo.data.code, 'P0409');
      assert.equal(firmaIntencion(c), intencionAntes);
      assert.equal(firmaSaga(c), sagaAntes);
      assert.equal(sql(`select estado from crm.inversionistas where id=${q(c.persona)}`), 'activo');
      c.perfil = ok(await llamarHandler(normal, c.solicitud, t, c.tokenSaga), 'Recuperar antes de fusionar').perfil_id;
    }
    const intencionAntes = firmaIntencion(c);
    const sagaAntes = firmaSaga(c);
    const contratoAntes = c.resultado ? sql(`select md5(to_jsonb(ct)::text) from public.contratos ct where id=${q(c.resultado.fuente.id)}`) : null;
    const jobAntes = c.resultado ? sql(`select md5(to_jsonb(j)::text) from private.contrato_pdf_jobs j where contrato_id=${q(c.resultado.fuente.id)}`) : null;
    assert.equal((await rpc('fusion_previsualizar_fn', { p_perdedora: c.persona, p_canonica: c.canonica.persona }, t)).data.code, '42501');
    c.fusion = await fusionar(c.persona, c.canonica.persona, gerente);
    assert.equal(firmaIntencion(c), intencionAntes);
    assert.equal(firmaSaga(c), sagaAntes);
    assert.equal(contenidoCierre(c), antecedente);
    assert.equal((await leerPreparada(c, t)).data.code, '42501');
    assert.equal((await llamarHandler(normal, c.solicitud, t, c.tokenSaga)).status, 403);
    assert.equal((await rpc('confirmar_inversion_fn', { p_solicitud: c.solicitud }, t)).data.code, '42501');
    const lectura = ok(await leerPreparada(c, nuevo), 'Continuar desde la identidad canónica');
    assert.equal(lectura.inversionista_id, c.canonica.persona);
    assert.equal(lectura.inversionista_origen_id, c.persona);
    assert.equal(lectura.identidad_fusionada, true);
    assert.equal(lectura.requiere_revision_responsable, corte !== 'confirmada');
    if (corte !== 'confirmada') {
      assert.equal((await rpc('confirmar_inversion_fn', { p_solicitud: c.solicitud }, nuevo)).data.code, 'P0409');
      ok(await revisar(c, f.usuarios.ajeno.id, 0, nuevo), 'Revisar responsable de la canónica');
      assert.equal(firmaIntencion(c), intencionAntes);
      assert.equal(firmaSaga(c), sagaAntes);
    }
    c.perfil = ok(await llamarHandler(normal, c.solicitud, nuevo, c.tokenSaga), 'Recuperar/reutilizar Portal tras fusión').perfil_id;
    let actual = c.canonica.persona;
    let actor = nuevo;
    let responsable = f.usuarios.ajeno.id;
    if (corte === 'sin_auth') {
      // La solicitud nació en P, Auth se creó después en C y ahora C se fusiona
      // en D. Recuperar por P o D no debe inventar un segundo claim/usuario.
      assert.equal(sql(`select auth_contexto->>'inversionista_id' from crm.inversion_solicitudes where id=${q(c.solicitud)}`), actual);
      c.tercera = await nuevaCanonica(f.usuarios.vendedor.id, 'PASAPORTE');
      const sagaIntermedia = firmaSaga(c);
      const intencionIntermedia = firmaIntencion(c);
      c.segundaFusion = await fusionar(actual, c.tercera.persona, gerente);
      actual = c.tercera.persona;
      actor = t;
      responsable = f.usuarios.vendedor.id;
      assert.equal(firmaSaga(c), sagaIntermedia);
      assert.equal(firmaIntencion(c), intencionIntermedia);
      assert.equal((await leerPreparada(c, nuevo)).data.code, '42501');
      ok(await revisar(c, responsable, 1, actor), 'Revisar después de la segunda fusión');
      assert.equal(firmaSaga(c), sagaIntermedia);
      assert.equal(firmaIntencion(c), intencionIntermedia);
      assert.equal(ok(await llamarHandler(normal, c.solicitud, actor), 'Reusar claim de la canónica intermedia').perfil_id, c.perfil);
    }
    const confirmado = ok(await rpc('confirmar_inversion_fn', { p_solicitud: c.solicitud }, actor), 'Confirmar tras fusión');
    assert.equal(confirmado.inversionista_id, actual);
    comprobarPrincipal(c, confirmado, actual);
    if (c.resultado) {
      assert.equal(confirmado.inversion_id, c.resultado.inversion_id);
      assert.equal(sql(`select md5(to_jsonb(ct)::text) from public.contratos ct where id=${q(confirmado.fuente.id)}`), contratoAntes);
      assert.equal(sql(`select md5(to_jsonb(j)::text) from private.contrato_pdf_jobs j where contrato_id=${q(confirmado.fuente.id)}`), jobAntes);
    }
    assert.equal(sql(`select analista_cierre_id from public.contratos where id=${q(confirmado.fuente.id)}`), corte === 'confirmada' ? f.usuarios.vendedor.id : responsable);
    assert.equal(sql(`select count(*) from auth.users where lower(email)=${q(c.datos.alta_portal.correo)}`), '1');
    assert.equal(sql(`select count(*) from crm.inversiones where inversionista_id=${q(actual)} and contrato_id is not null`), '1');
    const repetido = ok(await rpc('confirmar_inversion_fn', { p_solicitud: c.solicitud }, actor), 'Repetir tras fusión');
    assert.equal(repetido.inversion_id, confirmado.inversion_id);
    assert.equal(ok(await leerPreparada(c, actor), 'Leer resultado desde solicitud original').resultado.inversionista_id, actual);
    c.resultado = confirmado;
    pruebas.push({ rama: 'avance', corte, fusionCanonicaReal: true, origenYHashConservados: true,
      ambitoActual: true, mismoPortal: true, fuenteYTitularEnCanonica: true,
      atribucionConfirmadaConservada: true, dobleFusionConClaimIntermedio: corte === 'sin_auth' });
    guardar(`fusion-${ejecucion}.json`, casos);
    console.log(`Conforme: fusión Avance en ${corte}, misma solicitud y acceso desde la canónica.`);
  }

  const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aT9sAAAAASUVORK5CYII=', 'base64');
  for (const corte of ['antes_subir', 'despues_subir', 'confirmada']) {
    const c = await prepararPersonaPortal({ vendedor: f.usuarios.vendedor.id, token: t, etiqueta: `fusion_cooperativa_${corte}` });
    c.canonica = await nuevaCanonica();
    c.datos = { inversionista_id: c.persona, empresa: 'prodelco', monto: 725, moneda: 'PEN',
      fecha_comercial: sql("select (statement_timestamp() at time zone 'America/Lima')::date"), vence_en: '2027-09-07',
      numero_transaccion: `F4-FUSION-${c.solicitud}`, referencia: 'EVIDENCIA FICTICIA DE FUSION',
      evidencia: { ruta: `${c.persona}/${c.solicitud}/comprobante.png` } };
    casos.push(c);
    guardar(`fusion-${ejecucion}.json`, casos);
    const subir = token => http(`/storage/v1/object/f4-comprobantes/${c.datos.evidencia.ruta}`, {
      token, rawBody: png, headers: { 'Content-Type': 'image/png' },
    });
    const descargar = token => http(`/storage/v1/object/authenticated/f4-comprobantes/${c.datos.evidencia.ruta}`, {
      token, method: 'GET', binary: true,
    });
    ok(await leerPreparada(c, t), 'Preparar cooperativa antes de fusionar');
    if (corte !== 'antes_subir') ok(await subir(t), 'Subir comprobante antes de fusionar');
    if (corte === 'confirmada') c.resultado = ok(await rpc('confirmar_inversion_fn', { p_solicitud: c.solicitud }, t), 'Confirmar cooperativa antes de fusionar');
    const intencionAntes = firmaIntencion(c);
    c.fusion = await fusionar(c.persona, c.canonica.persona, gerente);
    assert.equal(firmaIntencion(c), intencionAntes);
    assert.equal((await leerPreparada(c, t)).data.code, '42501');
    assert.equal((await descargar(t)).ok, false);
    if (corte !== 'confirmada') ok(await revisar(c, f.usuarios.ajeno.id, 0, nuevo), 'Revisar cooperativa después de fusionar');
    if (corte === 'antes_subir') {
      assert.equal((await subir(t)).ok, false);
      ok(await subir(nuevo), 'Subir en la ruta original con permisos actuales');
    }
    assert.deepEqual(ok(await descargar(nuevo), 'Descargar evidencia con permisos de canónica'), png);
    const confirmado = ok(await rpc('confirmar_inversion_fn', { p_solicitud: c.solicitud }, nuevo), 'Confirmar/repetir cooperativa desde canónica');
    assert.equal(confirmado.inversionista_id, c.canonica.persona);
    comprobarPrincipal(c, confirmado, c.canonica.persona);
    if (c.resultado) assert.equal(confirmado.inversion_id, c.resultado.inversion_id);
    const fuente = JSON.parse(sql(`select jsonb_build_object('monto',monto,'moneda',moneda,'responsable',vendedor_id,'ruta',o.name)
      from crm.cierres_externos ce join storage.objects o on o.id=ce.comprobante_objeto_id where ce.id=${q(confirmado.fuente.cierre_id)}`));
    assert.deepEqual(fuente, { monto: 725, moneda: 'PEN',
      responsable: corte === 'confirmada' ? f.usuarios.vendedor.id : f.usuarios.ajeno.id, ruta: c.datos.evidencia.ruta });
    assert.equal(sql(`select count(*) from crm.depositos_reclamados where numero_norm=${q(c.datos.numero_transaccion.toUpperCase())}`), '1');
    assert.equal(sql(`select count(*) from crm.cierres_externos where inversionista_id=${q(c.canonica.persona)} and not es_cierre_inicial`), '1');
    c.resultado = confirmado;
    guardar(`fusion-${ejecucion}.json`, casos);
    pruebas.push({ rama: 'cooperativa', corte, fusionCanonicaReal: true, comprobanteOriginalConservado: true,
      permisosDeCanonica: true, depositoUnico: true, fuenteTitularYAtribucionCorrectos: true });
    console.log(`Conforme: fusión cooperativa en ${corte}, evidencia original y permisos actuales.`);
  }
  assert.equal(sql("select md5(prosrc) from pg_proc where oid='crm.fusionar_inversionistas_fn(uuid,uuid,text,text)'::regprocedure"), huellaFusion);
  writeFileSync(new URL(`../evidencia-f4/fusion-${ejecucion}.json`, import.meta.url), JSON.stringify({
    entorno, ejecucion, terminadoEn: new Date().toISOString(), pruebas,
    fusionPublicadaSinCambios: huellaFusion,
    limite: 'Fusión viable por F3: una sola ficha comercial y un solo perfil. Se mantiene el bloqueo por Auth no terminal; lectores heredados, carreras y PDF se verifican aparte.',
  }, null, 2) + '\n');
} finally {
  sql(`update crm.multiempresa_flags set activo=${bandera === 't'} where nombre='inversiones_escritura'`);
}
