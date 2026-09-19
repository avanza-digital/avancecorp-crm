// Mismas aserciones que http.test.mjs; sólo cambia transporte/destino fijo.
import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID,randomInt,randomBytes} from 'node:crypto';
import {writeFileSync} from 'node:fs';
import {spawn} from 'node:child_process';
import {once} from 'node:events';
import {sql,q,objeto,psql,env} from './banco-remoto.mjs';
import {apiUrl,inicio,fixture,como,rpc,http,carpeta} from './banco-remoto.mjs';
import {contratoPrueba} from '../../f4/operaciones-fixture.mjs';
import {crearHandlerAccesoInversion} from '../../../../../_supabase_functions/functions/crm-inversion-portal/handler.mjs';
import {crearHandlerBienvenida} from '../../../functions/crm-inversion-bienvenida/handler.mjs';
const ok=(r,n='RPC')=>{assert.equal(r.ok,true,`${n}: ${r.status} ${r.data?.message??r.data?.error??''}`);return r.data;};
const png=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aUN0AAAAASUVORK5CYII=','base64');
const fecha=sql("select (now() at time zone 'America/Lima')::date");
const fin=fecha.replace(/^\d{4}/,String(Number(fecha.slice(0,4))+1));
const evidencia={fecha:new Date().toISOString(),casos:[],leads:[],limite:'Rama remota exclusiva autorizada, proyecto omdgdbsbsabisykekziu. HTTP Auth/PostgREST/Storage reales; sin correo ni producción.'};
function leadNuevo(){
  const id=randomUUID(),documento=String(randomInt(80000000,89999999));
  sql(`insert into crm.leads(id,nombre_completo,telefono,monto_estimado,etapa,vendedor_id,creado_por,origen)
    values(${q(id)},'PERSONA PRUEBA CONVERSION HTTP',${q('9'+randomInt(10000000,99999999))},5000,'propuesta_enviada',
      ${q(fixture.usuarios.vendedor.id)},${q(fixture.usuarios.vendedor.id)},'otro')`);
  evidencia.leads.push(id);return {id,documento};
}
const estadoLead=id=>objeto(`select to_jsonb(l) - 'telefono' - 'correo' - 'dni' from crm.leads l where id=${q(id)}`);
const capitalDeLead=id=>JSON.parse(sql(`begin;set local request.jwt.claim.sub=${q(fixture.usuarios.gerencia.id)};
  select coalesce(jsonb_agg(to_jsonb(c)),'[]') from private.capital_episodios(
    ${q(fecha.slice(0,8)+'01T00:00:00-05:00')},(${q(fecha)}::date+1)::timestamp at time zone 'America/Lima',true,null) c
    where lead_id=${q(id)} or contrato_id=(select contrato_id from crm.leads where id=${q(id)});rollback;`));
test('Conversión unificada: integración HTTP y aislamiento por rol',async t=>{
  const tokens=Object.fromEntries(await Promise.all(['vendedor','supervisor','supervisor_ajeno','gerencia','ajeno','directorio','cliente']
    .map(async r=>[r,await como(r)])));
  const llamada=(n,d,rol='vendedor')=>rpc(n,d,tokens[rol]);
  const reconocer=async(l,rol='vendedor')=>ok(await llamada('preparar_persona_lead_inversion_fn',
    {p_lead:l.id,p_tipo_documento:l.tipo??'DNI',p_documento:l.documento,p_nombre:'PERSONA PRUEBA CONVERSION HTTP'},rol));
  const caso=async(n,f)=>t.test(n,async()=>{await f();evidencia.casos.push(n);});
  let persona,primera,coop;
  try{
    await caso('ACL y ámbito: anon, cliente, Directorio y equipos ajenos no preparan identidad',async()=>{
      const l=leadNuevo(),payload={p_lead:l.id,p_tipo_documento:'DNI',p_documento:l.documento,p_nombre:'PERSONA PRUEBA'};
      assert.equal((await rpc('preparar_persona_lead_inversion_fn',payload)).ok,false);
      for(const rol of ['cliente','directorio','ajeno','supervisor_ajeno']){
        const r=await llamada('preparar_persona_lead_inversion_fn',payload,rol);
        assert.equal(r.ok,false,rol);assert.equal(r.data.code,'42501',rol);
      }
      assert.equal(estadoLead(l.id).inversionista_id,null);
      const s=await reconocer(l,'supervisor'),g=await reconocer(l,'gerencia');
      assert.equal(s.inversionista_id,g.inversionista_id);
      assert.equal(sql(`select responsable_relacion_id from crm.inversionistas where id=${q(s.inversionista_id)}`),fixture.usuarios.vendedor.id);
      const directo=await http(`/rest/v1/leads?id=eq.${l.id}`,{method:'PATCH',token:tokens.vendedor,body:{etapa:'convertido'},headers:{'Content-Profile':'crm'}});
      assert.equal(directo.ok,false);assert.equal(estadoLead(l.id).etapa,'propuesta_enviada');
      const vieja=await llamada('reservar_conversion_lead',{p_lead_id:l.id,p_tipo_documento:'DNI',p_documento:l.documento,
        p_payload:{correo:'conversion.legacy@example.test',nombre_completo:'PERSONA PRUEBA',nombres:'PERSONA',apellidos:'PRUEBA',domicilio:'AVENIDA SINTETICA 123 LIMA'}});
      assert.equal(vieja.ok,false);assert.match(vieja.data.message,/Actualiza el CRM/);
      assert.equal(sql(`select count(*) from crm.conversion_reservas where lead_id=${q(l.id)}`),'0');
      const anterior=await llamada('convertir_lead_externo',{p_lead_id:l.id,p_cooperativa:'prodelco',p_monto:5000,p_moneda:'USD',
        p_documento_tipo:'DNI',p_documento:l.documento,p_nombre:'PERSONA PRUEBA',p_numero_transaccion:randomUUID()});
      assert.equal(anterior.ok,false);assert.match(anterior.data.message,/Actualiza el CRM/);
    });
    for(const [empresa,moneda] of [['qorilazo','PEN'],['prodelco','PEN'],['prodelco','USD']]){
      await caso(`${empresa} ${moneda}: comprobante real, doble envío y paridad de Cartera`,async()=>{
        const l=leadNuevo(),p=await reconocer(l);persona=p.inversionista_id;
        const id=randomUUID(),ruta=`${persona}/${id}/comprobante.png`;
        const d={inversionista_id:persona,lead_id:l.id,empresa,moneda,monto:5000,fecha_comercial:fecha,vence_en:fin,
          plazo_meses:12,tasa_anual:18,numero_transaccion:`CI-${id}`,referencia:'CERTIFICADO SINTETICO',evidencia:{ruta}};
        const preparados=await Promise.all([llamada('preparar_inversion_fn',{p_clave:id,p_datos:d}),llamada('preparar_inversion_fn',{p_clave:id,p_datos:d})]);
        assert(preparados.some(x=>x.ok));
        for(const r of preparados)if(!r.ok)assert(['55P03','P0409','40001'].includes(r.data.code));
        assert.equal(ok(await llamada('preparar_inversion_fn',{p_clave:id,p_datos:d})).solicitud_id,id);
        assert.equal(estadoLead(l.id).etapa,'propuesta_enviada');
        assert.equal((await reconocer(l)).solicitud_id,id);
        assert.equal((await llamada('preparar_inversion_fn',{p_clave:randomUUID(),p_datos:d})).ok,false);
        assert.equal((await llamada('confirmar_inversion_revisada_fn',{p_solicitud:id,p_revision_datos_esperada:0})).ok,false);
        for(const rol of ['ajeno','supervisor_ajeno','directorio','cliente']){
          assert.equal((await llamada('solicitud_inversion_fn',{p_solicitud:id},rol)).ok,false);
          assert.equal((await http(`/storage/v1/object/f4-comprobantes/${ruta}`,{token:tokens[rol],rawBody:png,headers:{'Content-Type':'image/png'}})).ok,false);
        }
        ok(await http(`/storage/v1/object/f4-comprobantes/${ruta}`,{token:tokens.vendedor,rawBody:png,headers:{'Content-Type':'image/png'}}),'Subir comprobante');
        const confirmados=await Promise.all([llamada('confirmar_inversion_revisada_fn',{p_solicitud:id,p_revision_datos_esperada:0}),
          llamada('confirmar_inversion_revisada_fn',{p_solicitud:id,p_revision_datos_esperada:0})]);
        assert(confirmados.some(x=>x.ok));
        const c=ok(await llamada('confirmar_inversion_revisada_fn',{p_solicitud:id,p_revision_datos_esperada:0}));
        for(const r of confirmados)if(r.ok)assert.equal(r.data.inversion_id,c.inversion_id);
        const recuperada=ok(await llamada('solicitud_inversion_fn',{p_solicitud:id}));
        assert.equal(recuperada.resultado.inversion_id,c.inversion_id);
        assert.equal((await reconocer(l)).solicitud_id,id,'respuesta perdida tras confirmar');
        assert.equal(ok(await llamada('contexto_conversion_inversion_fn',{p_lead:l.id,p_persona:persona})).capacidades.nueva_inversion,false);
        assert.equal(estadoLead(l.id).etapa,'convertido');
        assert.equal(sql(`select count(*) from crm.inversiones where inversionista_id=${q(persona)}`),'1');
        const ficha=ok(await llamada('inversionista_ficha_fn',{p_inversionista:persona}));
        assert(ficha.inversiones.some(x=>x.fuente_id===c.fuente.cierre_id&&x.empresa===empresa&&x.moneda===moneda));
        assert.equal(ficha.persona.responsable_id,fixture.usuarios.vendedor.id);
        const capital=capitalDeLead(l.id);
        assert(capital?.some(x=>x.moneda===moneda&&Number(x.monto)===5000&&x.analista_id===fixture.usuarios.vendedor.id),'capital comercial');
        primera=c;coop={l,persona,d,id};
        // Entrada posterior desde Cartera: mismo validador, escritor y comprobante.
        const siguiente=randomUUID(),ad={...d,numero_transaccion:`CI-${siguiente}`,evidencia:{ruta:`${persona}/${siguiente}/comprobante.png`}};
        delete ad.lead_id;
        ok(await llamada('preparar_inversion_fn',{p_clave:siguiente,p_datos:ad}));
        ok(await http(`/storage/v1/object/f4-comprobantes/${ad.evidencia.ruta}`,{token:tokens.vendedor,rawBody:png,headers:{'Content-Type':'image/png'}}));
        const a=ok(await llamada('confirmar_inversion_revisada_fn',{p_solicitud:siguiente,p_revision_datos_esperada:0}));
        assert.equal(sql(`select es_primera_conversion from crm.inversiones where id=${q(a.inversion_id)}`),'f');
        assert.equal(sql(`select count(*) from crm.lead_asignaciones where lead_id=${q(l.id)} and resultado='convertido'`),'1');
      });
    }
    await caso('Cancelar y cambiar moneda conserva el lead abierto; cancelar una confirmada conserva su inversión',async()=>{
      const l=leadNuevo(),p=await reconocer(l),id=randomUUID();
      const datos={...coop.d,inversionista_id:p.inversionista_id,lead_id:l.id,empresa:'prodelco',moneda:'PEN',
        numero_transaccion:`CI-${id}`,evidencia:{ruta:`${p.inversionista_id}/${id}/comprobante.png`}};
      ok(await llamada('preparar_inversion_fn',{p_clave:id,p_datos:datos}));
      for(const rol of ['ajeno','supervisor_ajeno','directorio','cliente'])
        assert.equal((await llamada('cancelar_solicitud_inversion_fn',{p_solicitud:id,p_revision_datos_esperada:0},rol)).ok,false);
      assert.equal((await llamada('cancelar_solicitud_inversion_fn',{p_solicitud:id,p_revision_datos_esperada:1})).ok,false);
      for(let i=0;i<2;i++)assert.equal(ok(await llamada('cancelar_solicitud_inversion_fn',{p_solicitud:id,p_revision_datos_esperada:0})).estado,'cancelada');
      assert.equal(estadoLead(l.id).etapa,'propuesta_enviada');assert.equal((await reconocer(l)).solicitud_id,null);
      const nuevo=randomUUID(),otra={...datos,moneda:'USD',numero_transaccion:`CI-${nuevo}`,evidencia:{ruta:`${p.inversionista_id}/${nuevo}/comprobante.png`}};
      ok(await llamada('preparar_inversion_fn',{p_clave:nuevo,p_datos:otra}));
      ok(await http(`/storage/v1/object/f4-comprobantes/${otra.evidencia.ruta}`,{token:tokens.vendedor,rawBody:png,headers:{'Content-Type':'image/png'}}));
      const c=ok(await llamada('confirmar_inversion_revisada_fn',{p_solicitud:nuevo,p_revision_datos_esperada:0}));
      const conservada=ok(await llamada('cancelar_solicitud_inversion_fn',{p_solicitud:nuevo,p_revision_datos_esperada:0}));
      assert.equal(conservada.estado,'confirmada');assert.equal(conservada.resultado.inversion_id,c.inversion_id);
      assert.equal(sql(`select count(*) from crm.inversiones where inversionista_id=${q(p.inversionista_id)}`),'1');
      assert.equal(estadoLead(l.id).etapa,'convertido');
    });
    await caso('Dos pestañas con claves diferentes preparan una sola conversión',async()=>{
      const l=leadNuevo(),p=await reconocer(l),ids=[randomUUID(),randomUUID()];
      const respuestas=await Promise.all(ids.map(id=>llamada('preparar_inversion_fn',{p_clave:id,p_datos:{...coop.d,
        inversionista_id:p.inversionista_id,lead_id:l.id,numero_transaccion:`CI-${id}`,evidencia:{ruta:`${p.inversionista_id}/${id}/comprobante.png`}}})));
      assert.equal(respuestas.filter(r=>r.ok).length,1);
      assert.equal(respuestas.find(r=>!r.ok).data.code,'P0409');
      assert.equal(sql(`select count(*) from crm.inversion_solicitudes where lead_origen_id=${q(l.id)}`),'1');
      assert.equal(estadoLead(l.id).etapa,'propuesta_enviada');
    });
    await caso('Fusionar después de preparar mantiene una única inversión de la persona canónica',async()=>{
      const l=leadNuevo(),p=await reconocer(l),id=randomUUID();
      const datos={...coop.d,inversionista_id:p.inversionista_id,lead_id:l.id,numero_transaccion:`CI-${id}`,
        evidencia:{ruta:`${p.inversionista_id}/${id}/comprobante.png`}};
      ok(await llamada('preparar_inversion_fn',{p_clave:id,p_datos:datos}));
      const doc='0'+String(randomInt(80000000,89999999));
      const canonica=sql(`begin;set local request.jwt.claim.sub=${q(fixture.usuarios.gerencia.id)};
        select private.inversionista_resolver('CE',${q(doc)},true,'ensayo_preparada_fusion');commit;`);
      ok(await llamada('reasignar_responsable_relacion_fn',{p_inversionista:canonica,p_nuevo_responsable:fixture.usuarios.vendedor.id,
        p_motivo:'Asignar persona canónica del ensayo de solicitud preparada'},'gerencia'));
      const vista=ok(await llamada('fusion_previsualizar_fn',{p_perdedora:p.inversionista_id,p_canonica:canonica},'gerencia'));
      assert.equal(vista.viable,true,JSON.stringify(vista.bloqueos));
      ok(await llamada('fusionar_inversionistas_fn',{p_perdedora:p.inversionista_id,p_canonica:canonica,p_hash:vista.hash,
        p_motivo:'Fusionar después de preparar y antes de confirmar la inversión sintética'},'gerencia'));
      assert.equal((await reconocer(l)).solicitud_id,id);
      ok(await http(`/storage/v1/object/f4-comprobantes/${datos.evidencia.ruta}`,{token:tokens.vendedor,rawBody:png,headers:{'Content-Type':'image/png'}}));
      const c=ok(await llamada('confirmar_inversion_revisada_fn',{p_solicitud:id,p_revision_datos_esperada:0}));
      assert.equal(c.inversionista_id,canonica);assert.equal(estadoLead(l.id).inversionista_id,canonica);
      assert.equal(sql(`select count(*) from crm.inversiones where inversionista_id=${q(canonica)} and es_primera_conversion`),'1');
    });
    await caso('El lector conserva permisos sin esperar locks del escritor; veto devuelve capacidad bloqueada',async()=>{
      const l=leadNuevo(),p=await reconocer(l);
      const candado=spawn(psql,['-XqAt','-v','ON_ERROR_STOP=1','-f','-'],{env});
      const terminado=once(candado,'exit');
      const listo=new Promise((resolve,reject)=>{
        const limite=setTimeout(()=>reject(new Error('No se adquirió el candado de ensayo')),5000);
        candado.stdout.on('data',b=>{if(b.toString().includes('CANDADO_LISTO')){clearTimeout(limite);resolve();}});
      });
      candado.stdin.write(`begin;select id from crm.inversionistas where id=${q(p.inversionista_id)} for update;
        select id from crm.leads where id=${q(l.id)} for update;select 'CANDADO_LISTO';\n`);
      try{
        await listo;
        const ctx=ok(await llamada('contexto_conversion_inversion_fn',{p_lead:l.id,p_persona:p.inversionista_id}));
        assert.equal(ctx.capacidades.nueva_inversion,true);
      }finally{candado.stdin.end('rollback;\n');await terminado;}
      ok(await llamada('marcar_no_contactar',{p_lead_id:l.id,p_motivo:'Veto sintético para comprobar capacidades sin perder la ficha'}));
      const veto=ok(await llamada('contexto_conversion_inversion_fn',{p_lead:l.id,p_persona:p.inversionista_id}));
      assert.equal(veto.capacidades.nueva_inversion,false);assert.match(veto.capacidades.motivo_no_operable,/No insistir/);
    });
    await caso('Identidad fusionada: recupera la misma conversión por su lead y documento original',async()=>{
      const doc='0'+String(randomInt(80000000,89999999));
      const canonica=sql(`begin;set local request.jwt.claim.sub=${q(fixture.usuarios.gerencia.id)};
        select private.inversionista_resolver('CE',${q(doc)},true,'ensayo_conversion_fusion');commit;`);
      ok(await llamada('reasignar_responsable_relacion_fn',{p_inversionista:canonica,p_nuevo_responsable:fixture.usuarios.vendedor.id,
        p_motivo:'Asignar identidad sintética canónica para el ensayo de conversión'},'gerencia'));
      const vista=ok(await llamada('fusion_previsualizar_fn',{p_perdedora:coop.persona,p_canonica:canonica},'gerencia'));
      assert.equal(vista.viable,true,JSON.stringify(vista.bloqueos));
      ok(await llamada('fusionar_inversionistas_fn',{p_perdedora:coop.persona,p_canonica:canonica,p_hash:vista.hash,
        p_motivo:'Fusionar identidades sintéticas para verificar la recuperación de una conversión'},'gerencia'));
      const recuperada=await reconocer(coop.l);
      assert.equal(recuperada.inversionista_id,canonica);assert.equal(recuperada.solicitud_id,coop.id);
      const solicitud=ok(await llamada('solicitud_inversion_fn',{p_solicitud:coop.id}));
      assert.equal(solicitud.inversionista_id,canonica);assert.equal(solicitud.identidad_fusionada,true);
      assert.equal(solicitud.resultado.inversion_id,primera.inversion_id);
      assert.equal(sql(`select count(*) from crm.inversiones where inversionista_id=${q(canonica)} and es_primera_conversion`),'1');
    });
    await caso('Reasignación después de preparar: el analista anterior pierde acceso',async()=>{
      const l=leadNuevo(),p=await reconocer(l),id=randomUUID();
      const d={...coop.d,lead_id:l.id,inversionista_id:p.inversionista_id,numero_transaccion:`CI-${id}`,
        evidencia:{ruta:`${p.inversionista_id}/${id}/comprobante.png`}};
      ok(await llamada('preparar_inversion_fn',{p_clave:id,p_datos:d}));
      ok(await llamada('reasignar_responsable_relacion_fn',{p_inversionista:p.inversionista_id,
        p_nuevo_responsable:fixture.usuarios.ajeno.id,p_motivo:'Trasladar la relación sintética a otro equipo'},'gerencia'));
      const r=await llamada('confirmar_inversion_revisada_fn',{p_solicitud:id,p_revision_datos_esperada:0});
      assert.equal(r.ok,false);assert.equal(r.data.code,'42501');
      assert.equal(estadoLead(l.id).etapa,'propuesta_enviada');
      const pendiente=ok(await llamada('solicitud_inversion_fn',{p_solicitud:id},'ajeno'));
      assert.equal(pendiente.requiere_revision_responsable,true);
      ok(await llamada('revisar_solicitud_inversion_fn',{p_solicitud:id,p_responsable_revisado:fixture.usuarios.ajeno.id,
        p_revision_esperada:pendiente.revision_responsable,p_motivo:'Verificar el responsable después del traslado de equipo'},'ajeno'));
      ok(await http(`/storage/v1/object/f4-comprobantes/${d.evidencia.ruta}`,{token:tokens.ajeno,rawBody:png,headers:{'Content-Type':'image/png'}}));
      const confirmado=ok(await llamada('confirmar_inversion_revisada_fn',{p_solicitud:id,p_revision_datos_esperada:0},'ajeno'));
      assert.equal(sql(`select vendedor_id from crm.cierres_externos where id=${q(confirmado.fuente.cierre_id)}`),fixture.usuarios.ajeno.id);
    });
    for(const [moneda,tipo] of [['PEN','DNI'],['USD','DNI'],['PEN','CE'],['USD','PASAPORTE']]){
      await caso(`Avance ${moneda} ${tipo}: Auth HTTP perdido y confirmación contractual única`,async()=>{
        const l=leadNuevo();l.tipo=tipo;
        if(tipo==='CE')l.documento='0'+l.documento;
        if(tipo==='PASAPORTE')l.documento='P'+l.documento;
        const p=await reconocer(l),id=randomUUID(),token=randomBytes(24).toString('hex');
        const d={inversionista_id:p.inversionista_id,lead_id:l.id,empresa:'avance',contrato:{moneda},cronograma:[],cuenta:{},
          alta_portal:{correo:`conversion.${id}@example.test`,nombre_completo:'PERSONA PRUEBA CONVERSION',nombres:'PERSONA',
            apellidos:'PRUEBA CONVERSION',telefono:'999888777',domicilio:'AVENIDA SINTETICA 123 LIMA'}};
        ok(await llamada('preparar_inversion_fn',{p_clave:id,p_datos:d}));
        assert.equal((await llamada('bienvenida_inversion_estado_fn',{p_solicitud:id})).ok,false);
        let perdida=false;
        const handler=crearHandlerAccesoInversion({supabaseUrl:apiUrl,anonKey:inicio.ANON_KEY,serviceKey:inicio.SERVICE_ROLE_KEY,
          fetchImpl:async(url,options)=>{
            const r=await fetch(url,options);
            if(!perdida&&String(url).endsWith('/rpc/acceso_inversion_fn')&&JSON.parse(options.body).p_paso==='reclamar'){
              assert.equal(r.ok,true);perdida=true;throw new TypeError('Respuesta HTTP perdida después del commit');
            }
            return r;
          }});
        const pedir=()=>handler(new Request(`${apiUrl}/functions/v1/crm-inversion-portal`,{method:'POST',headers:{Authorization:`Bearer ${tokens.vendedor}`},body:JSON.stringify({solicitud_id:id,token})}));
        const interrumpida=await pedir();assert.equal(interrumpida.status,503);assert(perdida);
        const cancelacion=await llamada('cancelar_solicitud_inversion_fn',{p_solicitud:id,p_revision_datos_esperada:0});
        assert.equal(cancelacion.ok,false);assert.match(cancelacion.data.message,/Completa el acceso/);
        const respuesta=await pedir(),acceso=await respuesta.json();assert.equal(respuesta.ok,true,acceso.error);
        assert.equal((await (await pedir()).json()).perfil_id,acceso.perfil_id);
        assert.equal(estadoLead(l.id).etapa,'propuesta_enviada');assert.equal(estadoLead(l.id).perfil_id,null);
        assert.equal(sql(`select count(*) from crm.inversiones where inversionista_id=${q(p.inversionista_id)}`),'0');
        const propuesta=contratoPrueba(acceso.perfil_id,fixture.usuarios.vendedor.id,{capital:1500,inicio:fecha.slice(0,8)+'01',moneda});
        delete propuesta.contrato.cliente_id;delete propuesta.contrato.analista_cierre_id;
        const completos={...d,...propuesta};
        ok(await llamada('corregir_solicitud_inversion_fn',{p_solicitud:id,p_clave:randomUUID(),p_revision_datos_esperada:0,p_datos:completos,p_motivo:'Completar condiciones contractuales después del acceso Avance'}));
        const c=ok(await llamada('confirmar_inversion_revisada_fn',{p_solicitud:id,p_revision_datos_esperada:1}));
        assert.equal(estadoLead(l.id).contrato_id,c.fuente.id);assert.equal(estadoLead(l.id).etapa,'convertido');
        // Recuperación desde el lead convertido, sin documento ni sessionStorage.
        const recuperado=ok(await llamada('contexto_conversion_inversion_fn',{p_lead:l.id}));
        assert.equal(recuperado.solicitud_id,id);assert.equal(recuperado.documento_tipo,tipo);
        assert.equal(ok(await llamada('confirmar_inversion_revisada_fn',{p_solicitud:id,p_revision_datos_esperada:1})).inversion_id,c.inversion_id);
        const ficha=ok(await llamada('inversionista_ficha_fn',{p_inversionista:p.inversionista_id}));
        assert(ficha.inversiones.some(x=>x.fuente_id===c.fuente.id&&x.moneda===moneda&&x.empresa==='avance'));
        assert.equal(sql(`select count(*) from public.cronograma_pagos where contrato_id=${q(c.fuente.id)}`),'13');
        const doc=capitalDeLead(l.id);
        assert(doc?.some(x=>x.moneda===moneda&&Number(x.monto)===1500&&x.analista_id===fixture.usuarios.vendedor.id));
        // Auth/PostgREST reales; sólo el proveedor de correo es un doble que
        // cumple su contrato de idempotencia. Nunca se envía correo externo.
        const entregas=new Map();let llamadasProveedor=0,perderRespuesta=true;
        const bienvenida=crearHandlerBienvenida({supabaseUrl:apiUrl,anonKey:inicio.ANON_KEY,serviceKey:inicio.SERVICE_ROLE_KEY,resendKey:'ensayo-sin-red',
          fetchImpl:async(url,options)=>{
            if(String(url)!=='https://api.resend.com/emails')return fetch(url,options);
            llamadasProveedor++;
            const clave=options.headers['Idempotency-Key'];assert.equal(clave,`conversion-bienvenida-v1/${id}`);
            if(entregas.has(clave))assert.equal(entregas.get(clave).body,options.body);
            else entregas.set(clave,{id:randomUUID(),body:options.body});
            if(perderRespuesta){perderRespuesta=false;throw new TypeError('Respuesta de proveedor perdida después del envío');}
            return Response.json({id:entregas.get(clave).id});
          }});
        const enviar=rol=>bienvenida(new Request(`${apiUrl}/functions/v1/crm-inversion-bienvenida`,{
          method:'POST',headers:{Authorization:`Bearer ${tokens[rol]}`},body:JSON.stringify({solicitud_id:id})}));
        for(const rol of ['ajeno','supervisor_ajeno','directorio','cliente'])assert.equal((await enviar(rol)).ok,false);
        assert.equal(llamadasProveedor,0);
        assert.equal((await llamada('bienvenida_inversion_entrega_fn',{p_solicitud:id,p_paso:'reclamar'})).ok,false,'sólo servicio entrega');
        assert.equal((await enviar('vendedor')).status,503);
        assert.equal(estadoLead(l.id).etapa,'convertido');
        assert.equal((await (await enviar('vendedor')).json()).estado,'en_proceso');
        assert.equal(llamadasProveedor,1);
        sql(`update crm.inversion_solicitudes set bienvenida=jsonb_set(bienvenida,'{lease_hasta}',to_jsonb(now()-interval '1 minute')) where id=${q(id)}`);
        assert.equal((await (await enviar('vendedor')).json()).estado,'enviada');
        assert.equal((await (await enviar('vendedor')).json()).estado,'enviada');
        assert.equal(llamadasProveedor,2);assert.equal(entregas.size,1,'el proveedor entregó una sola bienvenida');
        // Una entrega incierta pasada la ventana NO genera un correo nuevo.
        sql(`update crm.inversion_solicitudes set bienvenida=(bienvenida-'enviada_en')||
          jsonb_build_object('estado','en_proceso','primer_intento',now()-interval '25 hours','lease_hasta',now()-interval '1 hour') where id=${q(id)}`);
        assert.equal((await (await enviar('vendedor')).json()).estado,'verificar_entrega');
        assert.equal(llamadasProveedor,2);
      });
    }
  }finally{
    evidencia.terminado=new Date().toISOString();evidencia.inversionEjemplo=primera?.inversion_id;
    writeFileSync(`${carpeta}/evidencia-http.json`,JSON.stringify(evidencia,null,2)+'\n',{mode:0o600});
  }
});
