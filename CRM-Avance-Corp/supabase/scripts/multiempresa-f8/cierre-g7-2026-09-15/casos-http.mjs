// Casos ausentes en la muestra real. Solo banco fijo y datos sintéticos.
import assert from 'node:assert/strict';
import {randomUUID,randomInt,createHash} from 'node:crypto';
import {readFileSync,writeFileSync} from 'node:fs';
import {abrir,cerrar,db,apiUrl,fixture,sql,objeto,q,j,http,rpc,ok,sesion,handlerEnBanco,versiones} from './banco-http.mjs';
import {contratoPrueba} from '../../f4/operaciones-fixture.mjs';
import {crearHandlerAccesoInversion} from '../../../../../_supabase_functions/functions/crm-inversion-portal/handler.mjs';

const inicio=new Date().toISOString(),ejecucion=randomUUID(),resultados=[];
const archivo=new URL('casos-http.json',import.meta.url);
writeFileSync(archivo,JSON.stringify({estado:'RUNNING',inicio,banco:db})+'\n');
const tokens={};let flagsAntes,exito=false,tokenCruzado;
const png=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aT9sAAAAASUVORK5CYII=','base64');
const hoy=sql("select (now() at time zone 'America/Lima')::date");
const bien=(caso,evidencia={})=>{resultados.push({caso,estado:'PASS',...evidencia});console.log('PASS: '+caso);};
const llamar=(nombre,datos,rol='vendedor')=>rpc(nombre,datos,tokens[rol]);
const rechazo=(r,codigo)=>{assert.equal(r.ok,false);assert.equal(r.data.code,codigo,JSON.stringify(r.data));};
const preparar=(id,datos,rol='supervisor')=>llamar('preparar_inversion_fn',{p_clave:id,p_datos:datos},rol);
const confirmar=(id,rol='supervisor')=>llamar('confirmar_inversion_revisada_fn',{p_solicitud:id,p_revision_datos_esperada:0},rol);
const contadores=()=>objeto(`select jsonb_build_object('auth',(select count(*) from auth.users),
  'perfiles',(select count(*) from public.perfiles),'personas',(select count(*) from crm.inversionistas),
  'leads',(select count(*) from crm.leads),'contratos',(select count(*) from public.contratos),
  'inversiones',(select count(*) from crm.inversiones))`);
// La anulación comercial sí cambia estado/anulado; conserva importe, moneda,
// fecha, fuente y atribución. Esos dos campos se comprueban por separado.
const capital=fuente=>sql(`select coalesce(jsonb_agg(to_jsonb(c)-'estado'-'anulado' order by (to_jsonb(c)-'estado'-'anulado')::text),'[]')
  from private.capital_episodios('-infinity','infinity',true,'{}') c
  where c.contrato_id=${q(fuente)} or c.cierre_externo_id=${q(fuente)}`);
const saldo=()=>sql(`select md5(jsonb_build_object('contratos',(select jsonb_agg(to_jsonb(c) order by id)
  from public.contratos c),'cierres',(select jsonb_agg(to_jsonb(c) order by id) from crm.cierres_externos c))::text)`);
const estadoAcceso=id=>objeto(`select jsonb_build_object('estado',s.estado,'inversion',s.inversion_id,
  'saga',m.resultado->>'estado','perfil',i.perfil_id) from crm.inversion_solicitudes s
  join crm.inversionistas i on i.id=s.inversionista_id left join crm.multiempresa_idempotencia m
  on m.resultado->>'claim_id'=s.auth_claim_id::text where s.id=${q(id)}`);
async function handlerLlamar(handler,id,tokenSaga,tokenUsuario=tokens.supervisor) {
  const r=await handler(new Request(apiUrl+'/functions/v1/crm-inversion-portal',{
    method:'POST',headers:{'Content-Type':'application/json',...(tokenUsuario?{Authorization:'Bearer '+tokenUsuario}:{})},
    body:JSON.stringify({solicitud_id:id,...(tokenSaga?{token:tokenSaga}:{})})}));
  return {ok:r.ok,status:r.status,data:await r.json()};
}
async function personaNueva(empresa='qorilazo') {
  const lead=randomUUID();let documento;
  do {documento=String(randomInt(88000000,89999999));}
  while(sql(`select count(*) from crm.inversionista_identificadores where documento_normalizado=${q(documento)}`)!=='0');
  const nombre='PERSONA SINTETICA G7 '+lead.slice(0,8),v=fixture.usuarios.vendedor.id;
  sql(`insert into crm.leads(id,nombre_completo,telefono,monto_estimado,etapa,vendedor_id,creado_por,origen)
    values(${q(lead)},${q(nombre)},${q('9'+documento)},1000,'propuesta_enviada',${q(v)},${q(v)},'otro')`);
  const cierre=ok(await llamar('convertir_lead_externo',{p_lead_id:lead,p_cooperativa:empresa,p_monto:1000,
    p_moneda:'PEN',p_documento_tipo:'DNI',p_documento:documento,p_nombre:nombre,
    p_numero_transaccion:'G7-INICIAL-'+lead,p_referencia:'ANTECEDENTE SINTETICO',p_vence_en:null,
    p_nota:'Sin dinero real',p_plazo_meses:12,p_tasa_anual:12}));
  const persona=sql(`select inversionista_id from crm.leads where id=${q(lead)}`);
  assert.match(persona,/^[a-f0-9-]{36}$/);
  return {persona,lead,documento,nombre,cierre};
}
function datosCoop(persona,empresa,id,fecha=hoy,moneda='PEN') {
  return {inversionista_id:persona,empresa,monto:333,moneda,fecha_comercial:fecha,
    vence_en:sql(`select private.coopac_validar_condiciones(${q(fecha)},12,12)`),plazo_meses:12,tasa_anual:12,
    numero_transaccion:'G7-ADICIONAL-'+id,referencia:'COMPROBANTE SINTETICO',
    evidencia:{ruta:persona+'/'+id+'/comprobante.png'}};
}
async function cooperativa(persona,empresa,{fecha=hoy,moneda='PEN'}={}) {
  const id=randomUUID(),datos=datosCoop(persona,empresa,id,fecha,moneda);
  const antes=contadores();ok(await preparar(id,datos));
  ok(await http('/storage/v1/object/f4-comprobantes/'+datos.evidencia.ruta,{token:tokens.supervisor,
    bytes:png,headers:{'Content-Type':'image/png','x-upsert':'false'}}));
  const res=ok(await confirmar(id));assert.equal(res.inversionista_id,persona);
  const despues=contadores();
  for(const key of ['auth','perfiles','personas','leads','contratos'])assert.equal(despues[key],antes[key]);
  assert.equal(despues.inversiones,antes.inversiones+1);
  assert.equal(sql(`select count(*) from crm.inversiones where cierre_externo_id=${q(res.fuente.cierre_id)}`),'1');
  return {id,datos,res};
}
function datosAvance(p,id,{categoria='nuevo',inicio='2026-09-01',capital=1800,moneda='PEN'}={}) {
  const perfil=sql(`select coalesce(perfil_id::text,'') from crm.inversionistas where id=${q(p.persona)}`);
  return {inversionista_id:p.persona,empresa:'avance',
    ...contratoPrueba(perfil||null,fixture.usuarios.vendedor.id,{categoria,inicio,capital,moneda}),
    ...(!perfil?{alta_portal:{correo:'g7.'+id+'@pruebas.example',nombre_completo:p.nombre,
      telefono:'9'+p.documento,domicilio:'CALLE FICTICIA DEL ENSAYO 123, LIMA'}}:{})};
}
async function avanceNuevo(p,corte) {
  const id=randomUUID(),datos=datosAvance(p,id),antes=contadores();
  ok(await preparar(id,datos));
  const normal=handlerEnBanco(crearHandlerAccesoInversion);let recuperada;
  if(corte) {
    let interceptado=false;
    const conCorte=handlerEnBanco(crearHandlerAccesoInversion,async(url,opciones)=>{
      const r=await fetch(url,opciones);
      const paso=url.endsWith('/rest/v1/rpc/acceso_inversion_fn')?JSON.parse(opciones.body).p_paso:null;
      if(!interceptado&&r.ok&&((corte==='auth'&&url.endsWith('/auth/v1/admin/users'))||paso===corte)) {
        await r.clone().json();interceptado=true;throw new TypeError('Respuesta ya confirmada perdida por el ensayo');
      }return r;
    });
    const perdida=await handlerLlamar(conCorte,id);assert(interceptado);assert.equal(perdida.status,503);
    assert.match(perdida.data.token,/^[a-f0-9]{48}$/);
    const parcial=estadoAcceso(id);assert.equal(parcial.estado,'preparada');assert.equal(parcial.inversion,null);
    assert.equal(parcial.saga,{auth:'reclamado',registrar_auth:'auth_creado',crear_perfil:'perfil_creado',enlazar:'enlazado'}[corte]);
    const intermedios=contadores();assert.equal(intermedios.auth,antes.auth+1);
    assert.equal(intermedios.contratos,antes.contratos);assert.equal(intermedios.inversiones,antes.inversiones);
    for(const [usuario,status] of [[null,401],[tokens.ajeno,403],[tokens.cliente,403]]) {
      assert.equal((await handlerLlamar(normal,id,perdida.data.token,usuario)).status,status);
      assert.deepEqual(contadores(),intermedios);assert.deepEqual(estadoAcceso(id),parcial);
    }
    for(const incorrecto of [tokenCruzado,'0'.repeat(48)]) {
      const intento=await handlerLlamar(normal,id,incorrecto);
      // Una saga ya enlazada admite la lectura idempotente por un actor con
      // permiso aunque lleve un token obsoleto; no se reanuda ningún efecto.
      assert.equal(intento.status,corte==='enlazar'?200:409);
      assert.deepEqual(contadores(),intermedios);assert.deepEqual(estadoAcceso(id),parcial);
    }
    recuperada=ok(await handlerLlamar(normal,id,perdida.data.token));
  } else recuperada=ok(await handlerLlamar(normal,id));
  const res=ok(await confirmar(id)),perfil=recuperada.perfil_id;
  assert.equal(res.inversionista_id,p.persona);
  const propio=ok(await http('/auth/v1/token?grant_type=password',{body:{email:datos.alta_portal.correo,password:p.documento}}));
  assert.equal(propio.user.id,perfil);
  assert.equal(sql(`select debe_cambiar_password from public.perfiles where id=${q(perfil)}`),'t');
  assert.deepEqual(ok(await http('/rest/v1/contratos?id=eq.'+res.fuente.id+'&select=id',
    {method:'GET',token:propio.access_token})),[{id:res.fuente.id}]);
  assert.deepEqual(ok(await http('/rest/v1/contratos?id=eq.'+res.fuente.id+'&select=id',
    {method:'GET',token:tokens.ajeno})),[]);
  assert.equal(ok(await handlerLlamar(normal,id)).perfil_id,perfil);
  assert.equal(ok(await confirmar(id)).inversion_id,res.inversion_id);
  const despues=contadores();
  for(const key of ['auth','perfiles','contratos','inversiones'])assert.equal(despues[key],antes[key]+1);
  for(const key of ['personas','leads'])assert.equal(despues[key],antes[key]);
  assert.equal(sql(`select responsable_relacion_id from crm.inversionistas where id=${q(p.persona)}`),fixture.usuarios.vendedor.id);
  assert.equal(sql(`select analista_cierre_id from public.contratos where id=${q(res.fuente.id)}`),fixture.usuarios.vendedor.id);
  return {...p,perfil,id,datos,res};
}
async function ficha(persona) {
  const esperadas=objeto(`select jsonb_agg(jsonb_build_object('fuente_id',f.fuente_id,'empresa',f.empresa,
    'moneda',f.moneda,'capital',f.capital) order by f.fuente_id) from private.cartera_f5_fuentes_reales() f
    where f.inversionista_id=${q(persona)}`);
  const totales=objeto(`select jsonb_agg(to_jsonb(t) order by empresa,moneda) from (
    select empresa,moneda,count(*) cantidad,sum(capital) capital_registrado
    from private.cartera_f5_fuentes_reales() where inversionista_id=${q(persona)} group by empresa,moneda) t`);
  for(const rol of ['vendedor','supervisor','gerencia']) {
    const f=ok(await llamar('inversionista_ficha_fn',{p_inversionista:persona},rol));
    assert.equal(f.inversiones_total,esperadas.length);
    const vistas=f.inversiones.map(({fuente_id,empresa,moneda,capital})=>({fuente_id,empresa,moneda,capital}));
    vistas.sort((a,b)=>a.fuente_id.localeCompare(b.fuente_id));assert.deepEqual(vistas,esperadas);
    assert.deepEqual(f.totales.map(({empresa,moneda,cantidad,capital_registrado})=>({empresa,moneda,cantidad,capital_registrado}))
      .sort((a,b)=>(a.empresa+a.moneda).localeCompare(b.empresa+b.moneda)),totales);
  }
  // La RPC devuelve null fuera del ámbito, sin revelar si la persona existe.
  assert.equal(ok(await llamar('inversionista_ficha_fn',{p_inversionista:persona},'ajeno')),null);
}

try {
  await abrir();
  for(const rol of Object.keys(fixture.usuarios))tokens[rol]=await sesion(rol);
  flagsAntes=objeto('select jsonb_object_agg(nombre,activo) from crm.multiempresa_flags');
  assert.equal(sql('select activo from crm.piloto_f8_control where singleton'),'f');
  sql(`begin;update crm.multiempresa_flags set activo=(nombre in('resolver_en_puertas','inversiones_escritura','ficha_360_neutral','postventa_neutral'));
    update public.perfiles set telefono='999111222' where id in(${q(fixture.usuarios.gerencia.id)},${q(fixture.usuarios.supervisor.id)}) and telefono is null;commit;`);
  // Cuatro fallos tras escrituras reales; no se simula el resultado de Auth/SQL.
  const otra=await personaNueva(),otraSolicitud=randomUUID();
  ok(await preparar(otraSolicitud,datosAvance(otra,otraSolicitud)));
  tokenCruzado=ok(await llamar('acceso_inversion_fn',{p_solicitud:otraSolicitud,p_paso:'reclamar',p_payload:{}},'supervisor')).token;
  assert.match(tokenCruzado,/^[a-f0-9]{48}$/);
  const nuevos=[];
  for(const corte of ['auth','registrar_auth','crear_perfil','enlazar']) {
    const p=await personaNueva();nuevos.push(await avanceNuevo(p,corte));
    bien('Qorilazo → Avance: recuperación tras '+corte,{auth_unico:true,inversion_unica:true,portal_propio:true,ajeno_denegado:true});
  }
  const a=nuevos[0];
  await cooperativa(a.persona,'qorilazo');bien('Avance → Qorilazo',{persona_y_auth_conservados:true});
  const p2=await personaNueva();const qp=await cooperativa(p2.persona,'prodelco');bien('Qorilazo → Prodelco');
  await cooperativa(p2.persona,'qorilazo');bien('Segunda inversión en Qorilazo');
  const p3=await personaNueva('prodelco');await avanceNuevo(p3);bien('Prodelco → Avance');
  const monedaNoAdmitida=randomUUID();
  rechazo(await preparar(monedaNoAdmitida,datosCoop(a.persona,'prodelco',monedaNoAdmitida,hoy,'USD')),'22023');
  assert.equal(sql(`select count(*) from crm.inversion_solicitudes where id=${q(monedaNoAdmitida)}`),'0');
  await cooperativa(a.persona,'prodelco');bien('Avance → Prodelco; COOPAC rechaza USD sin guardar solicitud');
  const usd=randomUUID();ok(await preparar(usd,datosAvance(a,usd,{moneda:'USD',capital:1200})));
  ok(await confirmar(usd));bien('Inversión adicional Avance USD');
  await ficha(a.persona);await ficha(p2.persona);bien('Fichas por tres roles y ámbito ajeno',{personas:2,roles:3,monedas_separadas:true});

  // El trámite de retiro no liquida ni altera saldos.
  const dinero=saldo();
  const retirada={p_clave:randomUUID(),p_inversionista:p2.persona,p_fuente:qp.res.fuente.cierre_id,p_motivo:'Solicitud ficticia para cierre G7'};
  const retiro=ok(await llamar('postventa_solicitar_retiro_fn',retirada)).retiro;
  assert.deepEqual(ok(await llamar('postventa_solicitar_retiro_fn',retirada)).retiro,retiro);
  rechazo(await llamar('postventa_solicitar_retiro_fn',{...retirada,p_clave:randomUUID()}),'P0409');
  const rev={p_clave:randomUUID(),p_retiro:retiro.id,p_revision:1,p_estado:'en_revision',p_detalle:'Revisión ficticia de Gerencia'};
  rechazo(await llamar('postventa_revisar_retiro_fn',rev),'42501');
  assert.equal(ok(await llamar('postventa_revisar_retiro_fn',rev,'gerencia')).retiro.estado,'en_revision');
  const fin={...rev,p_clave:randomUUID(),p_revision:2,p_estado:'revisada'};
  assert.equal(ok(await llamar('postventa_revisar_retiro_fn',fin,'gerencia')).retiro.estado,'revisada');
  assert.equal(ok(await llamar('postventa_revisar_retiro_fn',fin,'gerencia')).retiro.revision,3);
  assert.equal(saldo(),dinero);bien('Retiro: permisos, reintentos y capital sin cambios');

  const capAntes=capital(qp.res.fuente.cierre_id);
  ok(await llamar('anular_cierre_externo',{p_cierre_id:qp.res.fuente.cierre_id,p_motivo:'Anulación comercial sintética G7'},'gerencia'));
  assert.equal(sql(`select estado from crm.inversiones where id=${q(qp.res.inversion_id)}`),'anulada');
  assert.equal(sql(`select anulado from private.capital_episodios('-infinity','infinity',true,'{}')
    where cierre_externo_id=${q(qp.res.fuente.cierre_id)} and medida='stock'`),'t');
  assert.equal(sql(`select count(*) from crm.inversion_eventos where inversion_id=${q(qp.res.inversion_id)} and tipo='anulacion'`),'1');
  assert.equal(capital(qp.res.fuente.cierre_id),capAntes);bien('Anulación comercial conserva Capital y deja un evento');

  // Estado provisional inyectado explícitamente como fixture, no como alta real.
  const provisional=await personaNueva();
  sql(`update crm.inversionista_identificadores set verificado=false where inversionista_id=${q(provisional.persona)};`);
  const sinIdentidad=randomUUID(),datos=datosCoop(provisional.persona,'prodelco',sinIdentidad);
  const previo=contadores(),bloqueo=await preparar(sinIdentidad,datos);
  rechazo(bloqueo,'P0409');assert.equal(bloqueo.data.message,'La inversión requiere un documento verificado');
  assert.deepEqual(contadores(),previo);
  assert.equal(sql(`select count(*) from crm.inversion_solicitudes where id=${q(sinIdentidad)}`),'0');
  sql(`update crm.inversionista_identificadores set verificado=true where inversionista_id=${q(provisional.persona)} and estado='vigente'`);
  await cooperativa(provisional.persona,'prodelco');bien('Identidad provisional bloquea alta; verificada permite continuar',{fixture_explicito:true});

  // Cotitular: una titularidad documental no duplica el capital ni concede acceso.
  const cot=await personaNueva(),coid=randomUUID(),codatos=datosAvance(a,coid,{capital:1500});
  codatos.contrato.titulares=[{nombre_completo:cot.nombre,tipo_documento:'DNI',documento:cot.documento}];
  const antesCot=contadores();ok(await preparar(coid,codatos));const co=ok(await confirmar(coid));
  assert.equal(sql(`select count(*) from public.contrato_titulares where contrato_id=${q(co.fuente.id)}`),'1');
  assert.equal(sql(`select count(*) from crm.inversion_titulares where inversion_id=${q(co.inversion_id)} and inversionista_id=${q(cot.persona)} and rol='cotitular'`),'1');
  assert.equal(contadores().personas,antesCot.personas);assert.equal(contadores().auth,antesCot.auth);
  assert.equal(sql(`select count(*) from private.capital_episodios('-infinity','infinity',true,'{}') where contrato_id=${q(co.fuente.id)} and medida='stock'`),'1');
  assert.equal(ok(await llamar('inversionista_ficha_fn',{p_inversionista:a.persona},'ajeno')),null);
  bien('Cotitularidad documental sin nueva persona, Auth ni doble stock');
  exito=true;
} finally {
  try {
    if(flagsAntes)sql(`begin;${Object.entries(flagsAntes).map(([nombre,activo])=>`update crm.multiempresa_flags set activo=${activo} where nombre=${q(nombre)};`).join('\n')}commit;`);
  } finally {await cerrar();}
  const recibo={estado:exito?'PASS':'FAIL',inicio,fin:new Date().toISOString(),banco:db,ejecucion,
    servicios:versiones,resultados,sha256:createHash('sha256').update(readFileSync(new URL(import.meta.url))).digest('hex'),
    dependencias_sha256:Object.fromEntries(['banco-http.mjs','dependencias-local.sql','../../f4/operaciones-fixture.mjs',
      '../../../../../_supabase_functions/functions/crm-inversion-portal/handler.mjs'].map(f=>[f,
      createHash('sha256').update(readFileSync(new URL(f,import.meta.url))).digest('hex')])),
    limites:['Datos sintéticos; no operaciones reales ni firma financiera.',
      'Auth, PostgREST y Storage reales locales; handler de producción ejecutado en Node, sin entrypoint Deno ni navegador.',
      'SQL administrativo solo para fixtures/configuración de la copia; operaciones comerciales mediante RPC HTTP authenticated.',
      'La copia conserva datos sintéticos; los servicios propios se detienen y eliminan. Sin GraphQL ni generación del PDF.']};
  writeFileSync(archivo,JSON.stringify(recibo,null,2)+'\n');
  console.log(JSON.stringify({estado:recibo.estado,grupos:resultados.length}));
}
