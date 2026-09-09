import test from 'node:test';
import assert from 'node:assert/strict';
import {randomInt, randomUUID, randomBytes} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {apiUrl, banco, como, guardar, http, leer, literal as q, rpc, sql} from './banco-local.mjs';
import {contratoPrueba} from '../f4/operaciones-fixture.mjs';
import {crearHandlerAccesoInversion} from '../../../../_supabase_functions/functions/crm-inversion-portal/handler.mjs';
import {crearHandlerDocumentoInversion} from '../../../../_supabase_functions/functions/crm-inversion-documento/handler.mjs';

const ok = (r, nombre = 'RPC F5') => {assert.equal(r.ok, true, `${nombre}: ${r.status} ${r.data?.message ?? r.data?.error ?? ''}`); return r.data;};
const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aUN0AAAAASUVORK5CYII=', 'base64');

test('G5: inversiones reales en banco sintético, recuperación y documentos', async t => {
  const f = leer('fixtures.json');
  const vendedor = await como('vendedor'), gerente = await como('gerencia'), ajeno = await como('ajeno'), directorio = await como('directorio');
  const inicio = JSON.parse(readFileSync(`${banco}/start.log`, 'utf8'));
  const config = {supabaseUrl: apiUrl, anonKey: inicio.ANON_KEY, serviceKey: inicio.SERVICE_ROLE_KEY};
  const flags = JSON.parse(sql('select jsonb_object_agg(nombre,activo) from crm.multiempresa_flags'));
  const llamada = (nombre, datos, token = vendedor) => rpc(nombre, datos, token);
  const detalle = id => llamada('inversionista_ficha_fn', {p_inversionista:id});
  const evidencia = {};
  let persona, perfil, primera, deposito;
  try {
    sql("update crm.multiempresa_flags set activo=true where nombre in ('resolver_en_puertas','inversiones_escritura','ficha_360_neutral')");
    await t.test('Qorilazo sin Portal: identidad visible sin bancos ni Auth inventados', async () => {
      const lead = randomUUID(), documento = `93${String(randomInt(1_000_000)).padStart(6, '0')}`;
      sql(`insert into crm.leads(id,nombre_completo,telefono,monto_estimado,etapa,vendedor_id,creado_por,origen)
        values(${q(lead)},'PERSONA SINTETICA F5 CARTERA','999888777',1000,'propuesta_enviada',${q(f.usuarios.vendedor.id)},${q(f.usuarios.vendedor.id)},'otro')`);
      ok(await llamada('convertir_lead_externo', {p_lead_id:lead,p_cooperativa:'qorilazo',p_monto:1000,p_moneda:'PEN',
        p_documento_tipo:'DNI',p_documento:documento,p_nombre:'PERSONA SINTETICA F5 CARTERA',
        p_numero_transaccion:`F5-INICIAL-${lead}`,p_referencia:'ANTECEDENTE SINTETICO F5',p_vence_en:'2027-09-08',p_nota:'Prueba sin dinero real'}));
      persona = sql(`select inversionista_id from crm.leads where id=${q(lead)}`);
      const d = ok(await detalle(persona));
      assert.equal(d.persona.perfil_id,null); assert.deepEqual(d.capacidades.cuentas_perfil_ids,[]);
      assert.equal(d.capacidades.nueva_inversion,true); assert.equal(d.inversiones.length,1);
    });
    await t.test('Qorilazo → Prodelco y repetición Qorilazo: mismo UUID, corrección y revisión obsoleta', async () => {
      for (const empresa of ['prodelco','qorilazo']) {
        const id=randomUUID(), ruta=`${persona}/${id}/comprobante.png`;
        const datos={inversionista_id:persona,empresa,monto:2100,moneda:'PEN',fecha_comercial:'2026-09-08',vence_en:'2027-09-09',
          numero_transaccion:`F5-${id}`,referencia:'DEPÓSITO SINTÉTICO F5',evidencia:{ruta}};
        const s=ok(await llamada('preparar_inversion_fn',{p_clave:id,p_datos:datos}));
        assert.equal(s.revision_datos,0);
        assert.equal(ok(await llamada('preparar_inversion_fn',{p_clave:id,p_datos:datos})).solicitud_id,id);
        assert.equal((await llamada('confirmar_inversion_revisada_fn',{p_solicitud:id,p_revision_datos_esperada:0})).ok,false);
        ok(await http(`/storage/v1/object/f4-comprobantes/${ruta}`,{token:vendedor,rawBody:png,headers:{'Content-Type':'image/png','x-upsert':'false'}}),'Subir comprobante');
        const correccion=randomUUID(), actual={...datos,monto:2300};
        const corregir={p_solicitud:id,p_clave:correccion,p_revision_datos_esperada:0,p_datos:actual,p_motivo:'Completar importe del depósito ficticio del ensayo'};
        assert.equal(ok(await llamada('corregir_solicitud_inversion_fn',corregir)).revision_datos,1);
        assert.equal(ok(await llamada('corregir_solicitud_inversion_fn',corregir)).revision_datos,1);
        assert.equal((await llamada('confirmar_inversion_revisada_fn',{p_solicitud:id,p_revision_datos_esperada:0})).data.code,'40001');
        const r=ok(await llamada('confirmar_inversion_revisada_fn',{p_solicitud:id,p_revision_datos_esperada:1}));
        // Se ignora deliberadamente la primera respuesta y se consulta como tras un corte.
        const recuperada=ok(await llamada('solicitud_inversion_fn',{p_solicitud:id}));
        assert.equal(recuperada.estado,'confirmada'); assert.equal(recuperada.resultado.inversion_id,r.inversion_id);
        assert.equal(ok(await llamada('confirmar_inversion_revisada_fn',{p_solicitud:id,p_revision_datos_esperada:1})).inversion_id,r.inversion_id);
        assert.equal(sql(`select count(*) from crm.inversiones where id=${q(r.inversion_id)}`),'1');
        deposito={datos,ruta,r};
      }
    });
    await t.test('depósito reclamado rechaza segunda inversión aunque cambie de cooperativa', async () => {
      const id=randomUUID(),ruta=`${persona}/${id}/repetido.png`;
      ok(await llamada('preparar_inversion_fn',{p_clave:id,p_datos:{...deposito.datos,empresa:'prodelco',evidencia:{ruta}}}));
      ok(await http(`/storage/v1/object/f4-comprobantes/${ruta}`,{token:vendedor,rawBody:png,headers:{'Content-Type':'image/png'}}));
      const r=await llamada('confirmar_inversion_revisada_fn',{p_solicitud:id,p_revision_datos_esperada:0});
      assert.equal(r.data.code,'P0409');
      assert.equal(sql(`select count(*) from crm.inversiones where cierre_externo_id in(select id from crm.cierres_externos where numero_transaccion=upper(${q(deposito.datos.numero_transaccion)}))`),'1');
    });
    await t.test('acceso Avance antes del contrato: Auth recuperable conserva contenido y usa corrección F4', async () => {
      const id=randomUUID(), token=randomBytes(24).toString('hex');
      const datos={inversionista_id:persona,empresa:'avance',contrato:{moneda:'PEN'},cronograma:[],cuenta:{},
        alta_portal:{correo:`f5.${id}@pruebas.example`,nombre_completo:'PERSONA SINTETICA F5 CARTERA',
          nombres:'PERSONA SINTETICA',apellidos:'F5 CARTERA',telefono:'999888777',domicilio:'CALLE SINTETICA DEL ENSAYO 123, LIMA'}};
      ok(await llamada('preparar_inversion_fn',{p_clave:id,p_datos:datos}));
      const handler=crearHandlerAccesoInversion(config);
      const pedir=()=>handler(new Request(`${apiUrl}/functions/v1/crm-inversion-portal`,{method:'POST',headers:{Authorization:`Bearer ${vendedor}`},body:JSON.stringify({solicitud_id:id,token})}));
      const acceso=await pedir(); const a=await acceso.json(); assert.equal(acceso.ok,true,a.error); perfil=a.perfil_id;
      const rec=await pedir(); assert.equal((await rec.json()).perfil_id,perfil);
      const borrador=contratoPrueba(perfil,f.usuarios.vendedor.id,{inicio:'2026-09-01',capital:1800});
      delete borrador.contrato.cliente_id; delete borrador.contrato.analista_cierre_id;
      const completos={...datos,...borrador};
      assert.equal(ok(await llamada('corregir_solicitud_inversion_fn',{p_solicitud:id,p_clave:randomUUID(),p_revision_datos_esperada:0,
        p_datos:completos,p_motivo:'Completar las condiciones contractuales tras el acceso Avance'})).revision_datos,1);
      primera=ok(await llamada('confirmar_inversion_revisada_fn',{p_solicitud:id,p_revision_datos_esperada:1}));
      const d=ok(await detalle(persona));
      assert.equal(d.persona.perfil_id,perfil);
      assert.deepEqual([...new Set(d.inversiones.map(x=>x.empresa))].sort(),['avance','prodelco','qorilazo']);
      evidencia.persona=persona; evidencia.perfil=perfil; evidencia.contrato=primera.fuente.id;
    });
    await t.test('Avance USD mantiene capital y moneda separados del PEN y cooperativas', async () => {
      const id=randomUUID(),d={inversionista_id:persona,empresa:'avance',...contratoPrueba(perfil,f.usuarios.vendedor.id,{inicio:'2026-09-01',capital:3400,moneda:'USD'})};
      ok(await llamada('preparar_inversion_fn',{p_clave:id,p_datos:d}));
      ok(await llamada('confirmar_inversion_revisada_fn',{p_solicitud:id,p_revision_datos_esperada:0}));
      const detalleActual=ok(await detalle(persona));
      for(const r of detalleActual.totales) {
        const esperado=Number(sql(`select coalesce(sum(capital),0) from private.cartera_f5_fuentes() where inversionista_id=${q(persona)} and empresa=${q(r.empresa)} and moneda=${q(r.moneda)} and not es_demo`));
        assert.equal(r.capital_registrado,esperado);
      }
      assert.ok(detalleActual.totales.some(x=>x.empresa==='avance' && x.moneda==='USD' && x.capital_registrado===3400));
    });
    await t.test('documentos F5 con escritura OFF: bytes exactos, permisos negativos y revocación durante descarga', async () => {
      const d=ok(await detalle(persona)), inversion=d.inversiones.find(x=>x.fuente_id===deposito.r.fuente.cierre_id);
      assert.ok(inversion.documentos.length);
      const input={inversionista_id:persona,fuente_id:inversion.fuente_id,documento_id:inversion.documentos[0].id};
      sql("update crm.multiempresa_flags set activo=false where nombre='inversiones_escritura'");
      const pedir=(handler,token)=>handler(new Request(`${apiUrl}/functions/v1/crm-inversion-documento`,{method:'POST',headers:{Authorization:`Bearer ${token}`,Origin:'https://crm.miavance.com'},body:JSON.stringify(input)}));
      const handler=crearHandlerDocumentoInversion(config), r=await pedir(handler,vendedor);
      assert.equal(r.ok,true); assert.deepEqual(Buffer.from(await r.arrayBuffer()),png);
      assert.equal(r.headers.get('Cache-Control'),'private, no-store');
      for(const token of [ajeno,directorio]) assert.equal((await pedir(handler,token)).status,403);
      let transferida=false;
      const durante=crearHandlerDocumentoInversion({...config,fetchImpl:async (url,init)=> {
        const res=await fetch(url,init);
        if(String(url).includes('/storage/v1/object/') && !transferida) {
          ok(await llamada('reasignar_responsable_relacion_fn',{p_inversionista:persona,p_nuevo_responsable:f.usuarios.ajeno.id,p_motivo:'Traslado ficticio durante la descarga documental del ensayo'},gerente)); transferida=true;
        }
        return res;
      }});
      try {assert.equal((await pedir(durante,vendedor)).status,403);}
      finally {if(transferida) ok(await llamada('reasignar_responsable_relacion_fn',{p_inversionista:persona,p_nuevo_responsable:f.usuarios.vendedor.id,p_motivo:'Restaurar responsable después del ensayo documental'},gerente));}
    });
  } finally {
    for(const [nombre,activo] of Object.entries(flags)) sql(`update crm.multiempresa_flags set activo=${activo} where nombre=${q(nombre)}`);
    guardar('evidencia-flujo.json',evidencia);
  }
});
