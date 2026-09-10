import test from 'node:test';
import assert from 'node:assert/strict';
import {randomInt,randomUUID} from 'node:crypto';
import {como,http,leer,literal as q,rpc,sql} from '../f5/banco-local.mjs';
const ok=r=>{assert.equal(r.ok,true,JSON.stringify(r.data));return r.data;};
const rechazar=(r,code)=>{assert.equal(r.ok,false);assert.equal(r.data.code,code,JSON.stringify(r.data));};
const png=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aUN0AAAAASUVORK5CYII=','base64');

test('F6: reinversión mantiene origen e idempotencia y conserva autores/capital',async t=>{
  const f=leer('fixtures.json'),token=await como('vendedor'),gerente=await como('gerencia');
  const llamar=(n,d,rol=token)=>rpc(n,d,rol);
  const flags=JSON.parse(sql('select jsonb_object_agg(nombre,activo) from crm.multiempresa_flags'));
  const lead=randomUUID(),documento=`92${String(randomInt(1000000)).padStart(6,'0')}`;
  let persona,origen,confirmada,entrada,ordinaria;
  const datos=id=>({inversionista_id:persona,empresa:'qorilazo',monto:1500,moneda:'PEN',
    fecha_comercial:new Date().toISOString().slice(0,10),vence_en:'2027-09-10',numero_transaccion:`F6-${id}`,
    referencia:'Depósito sintético F6',evidencia:{ruta:`${persona}/${id}/comprobante.png`}});
  const subir=d=>http(`/storage/v1/object/f4-comprobantes/${d.evidencia.ruta}`,{token,rawBody:png,headers:{'Content-Type':'image/png','x-upsert':'false'}}).then(ok);
  try {
    sql("update crm.multiempresa_flags set activo=true where nombre in ('resolver_en_puertas','inversiones_escritura','ficha_360_neutral','postventa_neutral')");
    await t.test('antecedente cooperativo propio del ensayo, sin cuenta ficticia Avance',async()=>{
      sql(`insert into crm.leads(id,nombre_completo,telefono,monto_estimado,etapa,vendedor_id,creado_por,origen)
        values(${q(lead)},'PERSONA SINTETICA REINVERSION F6','999888777',1000,'propuesta_enviada',${q(f.usuarios.vendedor.id)},${q(f.usuarios.vendedor.id)},'otro')`);
      ok(await llamar('convertir_lead_externo',{p_lead_id:lead,p_cooperativa:'qorilazo',p_monto:1000,p_moneda:'PEN',
        p_documento_tipo:'DNI',p_documento:documento,p_nombre:'PERSONA SINTETICA REINVERSION F6',
        p_numero_transaccion:`F6-ORIGEN-${lead}`,p_referencia:'ANTECEDENTE SINTETICO',p_vence_en:'2027-09-10',p_nota:'Sin dinero real'}));
      persona=sql(`select inversionista_id from crm.leads where id=${q(lead)}`);
      origen=sql(`select id from crm.cierres_externos where lead_id=${q(lead)}`);
      assert.equal(sql(`select perfil_id is null from crm.inversionistas where id=${q(persona)}`),'t');
    });
    await t.test('preparación y consulta recuperan origen; otra fuente con misma clave se rechaza',async()=>{
      const id=randomUUID();entrada={p_clave:id,p_fuente:origen,p_datos:datos(id)};
      const p=ok(await llamar('preparar_reinversion_fn',entrada));assert.equal(p.reinversion_origen_id,origen);
      assert.deepEqual(ok(await llamar('preparar_reinversion_fn',entrada)),p);
      rechazar(await llamar('preparar_reinversion_fn',{...entrada,p_fuente:randomUUID()}),'P0409');
      assert.equal(ok(await llamar('solicitud_inversion_fn',{p_solicitud:id})).reinversion_origen_id,origen);
    });
    await t.test('solicitud ordinaria nunca adquiere un origen retroactivo',async()=>{
      const id=randomUUID(),d=datos(id);ok(await llamar('preparar_inversion_fn',{p_clave:id,p_datos:d}));
      ordinaria=id;
      rechazar(await llamar('preparar_reinversion_fn',{p_clave:id,p_fuente:origen,p_datos:d}),'P0409');
      assert.equal(sql(`select count(*) from crm.inversion_solicitud_origenes where solicitud_id=${q(id)}`),'0');
    });
    await t.test('revisión obsoleta F6 responde HTTP 409 sin reintentos ni cambios parciales',async()=>{
      const antes=sql(`select to_jsonb(s) from crm.inversion_solicitudes s where id=${q(entrada.p_clave)}`);
      const inicio=Date.now();
      for(const [nombre,parametros] of [
        ['revisar_solicitud_inversion_fn',{p_solicitud:entrada.p_clave,p_responsable_revisado:f.usuarios.vendedor.id,p_revision_esperada:7,p_motivo:'Revisión obsoleta sintética'}],
        ['corregir_solicitud_inversion_fn',{p_solicitud:entrada.p_clave,p_clave:randomUUID(),p_revision_datos_esperada:7,p_datos:entrada.p_datos,p_motivo:'Corrección obsoleta sintética'}],
        ['confirmar_inversion_revisada_fn',{p_solicitud:entrada.p_clave,p_revision_datos_esperada:7}],
      ]){const r=await llamar(nombre,parametros);rechazar(r,'PT409');assert.equal(r.status,409);}
      assert.ok(Date.now()-inicio<10000,'Las revisiones obsoletas no deben entrar en reintentos automáticos');
      assert.equal(sql(`select to_jsonb(s) from crm.inversion_solicitudes s where id=${q(entrada.p_clave)}`),antes);
      assert.equal(sql(`select count(*) from crm.inversion_solicitud_revisiones where solicitud_id=${q(entrada.p_clave)}`),'0');
      assert.equal(sql(`select count(*) from crm.inversion_solicitud_correcciones where solicitud_id=${q(entrada.p_clave)}`),'0');
    });
    await t.test('consulta F6 traduce el conflicto heredado; F4 ordinaria conserva 40001',async()=>{
      // Inyección transaccional en el banco: sólo cambia la dependencia durante
      // estas llamadas SQL; el rollback restaura su cuerpo, ACL y configuración.
      const firma='private.inversion_persona_autorizada(uuid)';
      const antes=sql(`select md5(pg_get_functiondef(${q(firma)}::regprocedure))`);
      sql(`begin;
        do $inyeccion$ declare d text;b text;begin
          select pg_get_functiondef(oid),prosrc into d,b from pg_proc where oid=${q(firma)}::regprocedure;
          execute replace(d,b,'begin raise exception using errcode=''40001'',message=''Conflicto sintético de identidad''; end;');
        end $inyeccion$;
        set local role authenticated;
        select set_config('request.jwt.claims',${q(JSON.stringify({sub:f.usuarios.vendedor.id,role:'authenticated'}))},true);
        do $ensayo$ begin
          begin perform crm.solicitud_inversion_fn(${q(entrada.p_clave)});raise exception 'Falta conflicto F6';exception when sqlstate 'PT409' then null;end;
          begin perform crm.solicitud_inversion_fn(${q(ordinaria)});raise exception 'Cambió el contrato ordinario F4';exception when serialization_failure then null;end;
        end $ensayo$;
        rollback;`);
      assert.equal(sql(`select md5(pg_get_functiondef(${q(firma)}::regprocedure))`),antes);
    });
    await t.test('confirmar con comprobante produce una sola inversión nueva y traza la anterior',async()=>{
      await subir(entrada.p_datos);
      confirmada=ok(await llamar('confirmar_inversion_revisada_fn',{p_solicitud:entrada.p_clave,p_revision_datos_esperada:0}));
      const r=ok(await llamar('confirmar_inversion_revisada_fn',{p_solicitud:entrada.p_clave,p_revision_datos_esperada:0}));
      assert.equal(r.inversion_id,confirmada.inversion_id);
      assert.equal(sql(`select count(*) from crm.inversiones where id=${q(r.inversion_id)}`),'1');
      assert.equal(sql(`select count(*) from crm.inversionista_gestiones where tipo='reinversion' and metadata->>'solicitud_id'=${q(entrada.p_clave)}`),'1');
      assert.equal(sql(`select monto from crm.cierres_externos where id=${q(origen)}`),'1000.00');
    });
    await t.test('depósito reutilizado se rechaza también en reinversión',async()=>{
      const id=randomUUID(),d={...datos(id),numero_transaccion:entrada.p_datos.numero_transaccion};
      ok(await llamar('preparar_reinversion_fn',{p_clave:id,p_fuente:origen,p_datos:d}));await subir(d);
      rechazar(await llamar('confirmar_inversion_revisada_fn',{p_solicitud:id,p_revision_datos_esperada:0}),'P0409');
      assert.equal(sql(`select estado from crm.inversion_solicitudes where id=${q(id)}`),'preparada');
    });
    await t.test('anular origen bloquea pendientes y conserva la reinversión ya confirmada',async()=>{
      const id=randomUUID(),d=datos(id);ok(await llamar('preparar_reinversion_fn',{p_clave:id,p_fuente:origen,p_datos:d}));await subir(d);
      const antes=sql(`select to_jsonb(i) from crm.inversiones i where id=${q(confirmada.inversion_id)}`);
      ok(await llamar('anular_cierre_externo',{p_cierre_id:origen,p_motivo:'Anulación comercial sintética para validar la reinversión F6'},gerente));
      rechazar(await llamar('preparar_reinversion_fn',{p_clave:id,p_fuente:origen,p_datos:d}),'P0409');
      rechazar(await llamar('confirmar_inversion_revisada_fn',{p_solicitud:id,p_revision_datos_esperada:0}),'P0409');
      assert.equal(sql(`select estado from crm.inversion_solicitudes where id=${q(id)}`),'preparada');
      assert.equal(sql(`select to_jsonb(i) from crm.inversiones i where id=${q(confirmada.inversion_id)}`),antes);
      assert.equal(ok(await llamar('preparar_reinversion_fn',entrada)).inversion_id,confirmada.inversion_id);
    });
  } finally {for(const[nombre,activo]of Object.entries(flags))sql(`update crm.multiempresa_flags set activo=${activo} where nombre=${q(nombre)}`);}
});
