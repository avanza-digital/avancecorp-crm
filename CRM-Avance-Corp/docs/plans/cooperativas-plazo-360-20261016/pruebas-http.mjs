import assert from 'node:assert/strict'
import {randomUUID,randomInt} from 'node:crypto'
import {readFileSync,writeFileSync,existsSync} from 'node:fs'
import {dir,ref,rpc,http,sql,lote,q} from './banco.mjs'
const u=JSON.parse(readFileSync(dir+'/usuarios-privados.json','utf8'))
assert.equal(u.ref,ref)
const ruta=dir+'/pruebas-estado-privado.json'
const e=existsSync(ruta)?JSON.parse(readFileSync(ruta,'utf8')):{ref,fecha:new Intl.DateTimeFormat('sv-SE',{timeZone:'America/Lima'}).format(new Date()),casos:[],grupos:[]}
assert.equal(e.ref,ref)
const guardar=()=>writeFileSync(ruta,JSON.stringify(e),{mode:0o600})
const id=rol=>u.usuarios[rol].id
const token=rol=>u.tokens[rol]
const registrar=texto=>{if(!e.casos.includes(texto))e.casos.push(texto);guardar();console.log('PASS '+texto)}
const dias=(fecha,n)=>{const d=new Date(fecha+'T00:00:00Z');d.setUTCDate(d.getUTCDate()+n);return d.toISOString().slice(0,10)}
const meses=(fecha,n)=>{const [a,m,d]=fecha.split('-').map(Number);const fin=new Date(Date.UTC(a,m-1+n+1,0)).getUTCDate();return new Date(Date.UTC(a,m-1+n,Math.min(d,fin))).toISOString().slice(0,10)}
function ok(nombre,r){
  if(r.status!==200){writeFileSync(dir+'/fallo-rpc-privado.json',JSON.stringify({nombre,...r}),{mode:0o600});throw new Error(`${nombre}: HTTP ${r.status}, ${r.data?.code??''} ${r.data?.message??r.data?.error??''}`)}
  return r.data
}
async function llamada(nombre,datos,rol='analista'){return ok(nombre,await rpc(nombre,datos,token(rol)))}
async function rechaza(texto,nombre,datos,rol,codigo){
  const r=await rpc(nombre,datos,rol?token(rol):undefined)
  assert(r.status>=400,texto+': debe rechazar');assert.equal(r.data?.code,codigo,texto+': '+JSON.stringify(r.data));registrar(texto)
}
const fila=fuente=>JSON.parse(sql(`select to_jsonb(c) from crm.cierres_externos c where id=${q(fuente)}`))
const solicitud=clave=>JSON.parse(sql(`select to_jsonb(s) from crm.inversion_solicitudes s where id=${q(clave)}`))
async function lead(){
  const clave=randomUUID(),documento=String(randomInt(80000000,89999999));
  lote(`insert into crm.leads(id,nombre_completo,telefono,monto_estimado,moneda,etapa,vendedor_id,creado_por,origen)
    values(${q(clave)},'ENSAYO COOPAC360',${q('9'+String(randomInt(10000000,99999999)))},1000,'PEN','propuesta_enviada',${q(id('analista'))},${q(id('analista'))},'oficina');`)
  return {lead:clave,documento}
}
async function persona(){
  const l=await lead();const r=await llamada('preparar_persona_lead_inversion_fn',{
    p_lead:l.lead,p_tipo_documento:'DNI',p_documento:l.documento,p_nombre:'ENSAYO COOPAC360'})
  return {...l,persona:r.inversionista_id}
}
function datos(p,empresa,moneda,clave,vence,plazo=12){return {inversionista_id:p.persona,...(p.lead?{lead_id:p.lead}:{}),
  empresa,monto:1000,moneda,fecha_comercial:e.fecha,vence_en:vence,plazo_meses:plazo,tasa_anual:12.5,
  numero_transaccion:'C360-'+clave,referencia:'CERTIFICADO SINTETICO',evidencia:{ruta:p.persona+'/'+clave+'/comprobante.pdf'}}}
function pdf(){
  const c='BT /F1 12 Tf 30 100 Td (ENSAYO COOPAC 360) Tj ET';
  const objetos=['<</Type /Catalog /Pages 2 0 R>>','<</Type /Pages /Kids [3 0 R] /Count 1>>',
    '<</Type /Page /Parent 2 0 R /MediaBox [0 0 300 160] /Contents 4 0 R /Resources <</Font <</F1 5 0 R>>>>>>',
    `<</Length ${Buffer.byteLength(c)}>>\nstream\n${c}\nendstream`,'<</Type /Font /Subtype /Type1 /BaseFont /Helvetica>>'];
  let s='%PDF-1.4\n';const offsets=[0];for(const [i,o]of objetos.entries()){offsets.push(Buffer.byteLength(s));s+=`${i+1} 0 obj\n${o}\nendobj\n`}
  const xref=Buffer.byteLength(s);s+='xref\n0 6\n0000000000 65535 f \n'+offsets.slice(1).map(n=>String(n).padStart(10,'0')+' 00000 n \n').join('');
  return Buffer.from(s+`trailer\n<</Size 6 /Root 1 0 R>>\nstartxref\n${xref}\n%%EOF\n`)
}
async function comprobante(d){
  const r=await http('/storage/v1/object/f4-comprobantes/'+d.evidencia.ruta,{token:token('analista'),rawBody:pdf(),headers:{'Content-Type':'application/pdf','x-upsert':'false'}})
  assert.equal(r.status,200,'Storage sube comprobante sintético: '+JSON.stringify(r.data))
}
async function preparar(clave,d,fuente,tipo='upgrade'){
  return llamada(fuente?(tipo==='upgrade'?'preparar_upgrade_fn':'preparar_reinversion_fn'):'preparar_inversion_fn',{
    p_clave:clave,p_datos:d,...(fuente?{p_fuente:fuente}:{})})
}
const confirmar=(clave,revision=0,rol='analista')=>llamada('confirmar_inversion_revisada_fn',{p_solicitud:clave,p_revision_datos_esperada:revision},rol)

export async function antes(){
  assert.equal(sql("select md5(pg_get_functiondef('private.coopac_validar_condiciones(date,integer,numeric)'::regprocedure))"),'10ad4aaf7e96013a50273fd1ac47f5b7')
  let estado=await rpc('cartera_inversionistas_estado_fn',{},token('analista'))
  if(estado.data?.code==='PGRST106'){
    lote("alter role authenticator set pgrst.db_schemas='public,storage,graphql_public,crm'; notify pgrst,'reload config'; notify pgrst,'reload schema';")
    await new Promise(r=>setTimeout(r,1000));estado=await rpc('cartera_inversionistas_estado_fn',{},token('analista'))
  }
  assert.equal(ok('Disponibilidad',estado).habilitada,true)
  registrar('Auth real y RPC del CRM disponibles')
  if(!e.legacy){
    const l=await lead();const d={p_lead_id:l.lead,p_cooperativa:'qorilazo',p_monto:1000,p_moneda:'PEN',p_documento_tipo:'DNI',
      p_documento:l.documento,p_nombre:'ENSAYO COOPAC360',p_numero_transaccion:'C360-F3-'+l.lead,p_referencia:'ENSAYO F3',p_plazo_meses:12,p_tasa_anual:12.5}
    await rechaza('F3 obsoleto exige el formulario compartido','convertir_lead_externo',d,'analista','P0409')
    assert.equal(sql(`select count(*) from crm.cierres_externos where lead_id=${q(l.lead)}`),'0')
    e.legacy={datos:d,rechazado:true};guardar()
  }
  for(const [empresa,moneda]of [['qorilazo','PEN'],['prodelco','PEN'],['prodelco','USD']]){
    if(e.grupos.some(g=>g.empresa===empresa&&g.moneda===moneda))continue
    const p=await persona(),clave=randomUUID(),d=datos(p,empresa,moneda,clave,meses(e.fecha,12))
    await preparar(clave,d);await comprobante(d);const r=await confirmar(clave);const fuente=r.fuente.cierre_id
    const pendiente=randomUUID(),dPendiente=datos({persona:p.persona},empresa,moneda,pendiente,meses(e.fecha,12))
    await preparar(pendiente,dPendiente,fuente);await comprobante(dPendiente)
    const g={empresa,moneda,persona:p.persona,fuente,antes:fila(fuente),pendiente,datosPendientes:dPendiente,solicitudAntes:solicitud(pendiente)}
    assert.equal(g.antes.vence_en,meses(e.fecha,12));e.grupos.push(g);guardar();registrar(`${empresa} ${moneda}: contrato y borrador antiguos por Auth/RPC/Storage reales`)
  }
  e.antesCompleto=true;guardar();console.log('PASS FASE PREVIA: '+e.casos.length+' comprobaciones')
}

async function correccion(g,fuente,base,plazo){
  const original=fila(fuente)
  const lectura=await llamada('inversionista_gestion_fn',{p_inversionista:g.persona,p_fuente:fuente},'gerencia')
  const revision=lectura.inversion.coopac.revision
  assert.equal(revision,sql(`select md5(to_jsonb(c)::text) from crm.cierres_externos c where id=${q(fuente)}`))
  const d={monto:Number(original.monto),numero_transaccion:original.numero_transaccion,referencia:original.referencia_externa,nota:'CORRECCION SINTETICA',
    plazo_meses:plazo,tasa_anual:12.5,vence_en:original.vence_en}
  const args={p_inversionista:g.persona,p_fuente:fuente,p_clave:randomUUID(),p_revision:revision,p_datos:d}
  for(const rol of ['analista','supervisor','directorio','coordinador'])await rechaza(`${g.empresa} ${g.moneda}: ${rol} no corrige ${base}`,'inversionista_corregir_coopac_fn',args,rol,'42501')
  await llamada('inversionista_corregir_coopac_fn',args,'gerencia')
  const fin=fila(fuente);assert.equal(fin.base_plazo,base);assert.equal(fin.vence_en,base==='calendario'?meses(e.fecha,plazo):dias(e.fecha,plazo*30))
  assert.equal(fin.moneda,g.moneda);assert.equal(Number(fin.tasa_anual),12.5)
  await llamada('inversionista_corregir_coopac_fn',args,'gerencia');assert.deepEqual(fila(fuente),fin)
  await rechaza(`${g.empresa} ${g.moneda}: revisión antigua de ${base} rechazada`,'inversionista_corregir_coopac_fn',{...args,p_clave:randomUUID()},'gerencia','PT409')
  registrar(`${g.empresa} ${g.moneda}: Gerencia conserva base ${base} y reintento único`)
}

export async function despues(){
  assert.equal(e.antesCompleto,true)
  assert.equal(sql("select private.coopac_validar_condiciones('2026-01-31',12,12)::text"),'2027-01-26')
  await rechaza('F3 obsoleto sigue bloqueado tras el cambio','convertir_lead_externo',e.legacy.datos,'analista','P0409')
  assert.equal(sql(`select count(*) from crm.cierres_externos where lead_id=${q(e.legacy.datos.p_lead_id)}`),'0')
  for(const g of e.grupos){
    const antigua=fila(g.fuente),{base_plazo,...sinBase}=antigua;assert.equal(base_plazo,'calendario');assert.deepEqual(sinBase,g.antes)
    await rechaza(`${g.empresa} ${g.moneda}: borrador calendario exige revisión`,'confirmar_inversion_revisada_fn',{p_solicitud:g.pendiente,p_revision_datos_esperada:0},'analista','22023')
    assert.deepEqual(solicitud(g.pendiente),g.solicitudAntes)
    const nuevos={...g.datosPendientes,vence_en:dias(e.fecha,360)}
    const corregida=await llamada('corregir_solicitud_inversion_fn',{p_solicitud:g.pendiente,p_clave:randomUUID(),p_revision_datos_esperada:0,p_datos:nuevos,p_motivo:'Ajustar vencimiento al plazo de 360 días confirmado'})
    assert.equal(corregida.revision_datos,1)
    await rechaza(`${g.empresa} ${g.moneda}: confirmar revisión obsoleta se rechaza`,'confirmar_inversion_revisada_fn',{p_solicitud:g.pendiente,p_revision_datos_esperada:0},'analista','PT409')
    const r=await confirmar(g.pendiente,1),repetida=await confirmar(g.pendiente,1)
    assert.equal(r.inversion_id,repetida.inversion_id);assert.equal(repetida.reintento,true)
    const fuente=r.fuente.cierre_id,creada=fila(fuente);assert.equal(creada.base_plazo,'dias_360');assert.equal(creada.vence_en,dias(e.fecha,360));assert.deepEqual(fila(g.fuente),antigua)
    registrar(`${g.empresa} ${g.moneda}: upgrade de 360 días y origen intacto`)
    for(const rol of ['analista_ajeno','supervisor_ajeno','directorio','coordinador','inactivo','sin_equipo'])
      await rechaza(`${g.empresa} ${g.moneda}: ${rol} no confirma`,'confirmar_inversion_revisada_fn',{p_solicitud:g.pendiente,p_revision_datos_esperada:1},rol,'42501')
    await correccion(g,g.fuente,'calendario',6);await correccion(g,fuente,'dias_360',6)
    const ren=randomUUID(),dr=datos({persona:g.persona},g.empresa,g.moneda,ren,dias(e.fecha,360))
    await preparar(ren,dr,g.fuente,'reinversion');await comprobante(dr);const rr=await confirmar(ren)
    assert.equal(fila(rr.fuente.cierre_id).vence_en,dias(e.fecha,360));registrar(`${g.empresa} ${g.moneda}: reinversión usa 360 días`)
    const p=await persona(),n=randomUUID(),plazo=g.empresa==='qorilazo'?12:g.moneda==='PEN'?6:24,d=datos(p,g.empresa,g.moneda,n,dias(e.fecha,plazo*30),plazo)
    await preparar(n,d);await comprobante(d);const nuevo=await confirmar(n),nf=fila(nuevo.fuente.cierre_id)
    assert.equal(nf.vence_en,dias(e.fecha,plazo*30));assert.equal(nf.base_plazo,'dias_360');assert.equal(Number(nf.tasa_anual),12.5)
    registrar(`${g.empresa} ${g.moneda}: alta nueva de ${plazo*30} días`)
  }
  const l=await lead()
  await rechaza('F3 nuevo también exige el formulario compartido','convertir_lead_externo',{...e.legacy.datos,p_lead_id:l.lead,p_documento:l.documento,p_numero_transaccion:'C360-F3-'+l.lead},'analista','P0409')
  for(const rol of ['analista','supervisor','supervisor_ajeno','analista_ajeno','directorio','coordinador','inactivo','sin_equipo']){
    const r=await http('/rest/v1/cierres_externos?select=id',{method:'GET',token:token(rol),headers:{'Accept-Profile':'crm'}})
    assert(r.status>=400);assert.equal(r.data?.code,'42501');registrar(`${rol}: escritura privada sin lectura directa`)
  }
  await rechaza('Anónimo no confirma','confirmar_inversion_revisada_fn',{p_solicitud:e.grupos[0].pendiente,p_revision_datos_esperada:1},null,'42501')
  e.resultado='PASS';guardar();writeFileSync(dir+'/resultado-api.json',JSON.stringify({resultado:'PASS',casos:e.casos,fecha:e.fecha,grupos:e.grupos.map(g=>({empresa:g.empresa,moneda:g.moneda})),produccion_modificada:false},null,2))
  console.log('PASS ENSAYO AUTENTICADO: '+e.casos.length+' comprobaciones')
}

export async function fronteras(){
  assert.equal(e.resultado,'PASS');const g=e.grupos[0]
  const cantidad=sql('select count(*) from crm.cierres_externos')
  for(const [nombre,extra]of [['convención enviada por cliente',{base_plazo:'calendario'}],['vencimiento de 361 días',{vence_en:dias(e.fecha,361)}],['mes fraccionario',{plazo_meses:1.5}]]){
    const clave=randomUUID(),d={...datos({persona:g.persona},g.empresa,g.moneda,clave,dias(e.fecha,360)),...extra}
    await rechaza(`Servidor rechaza ${nombre}`,'preparar_upgrade_fn',{p_clave:clave,p_fuente:g.fuente,p_datos:d},'analista','22023')
    assert.equal(sql(`select count(*) from crm.inversion_solicitudes where id=${q(clave)}`),'0')
  }
  for(const rol of ['analista','gerencia']){
    const r=await http('/rest/v1/cierres_externos',{token:token(rol),body:{cooperativa:'qorilazo',monto:1,moneda:'PEN',base_plazo:'calendario'},headers:{'Content-Profile':'crm'}})
    assert(r.status>=400);assert.equal(r.data?.code,'42501',JSON.stringify(r.data));registrar(`${rol}: INSERT directo no permite elegir calendario`)
    const p=await http('/rest/v1/cierres_externos?id=eq.'+g.fuente,{token:token(rol),method:'PATCH',body:{base_plazo:'dias_360'},headers:{'Content-Profile':'crm'}})
    assert(p.status>=400);assert.equal(p.data?.code,'42501',JSON.stringify(p.data));registrar(`${rol}: UPDATE directo no cambia convención histórica`)
  }
  assert.equal(sql('select count(*) from crm.cierres_externos'),cantidad)
  guardar();writeFileSync(dir+'/resultado-api.json',JSON.stringify({resultado:'PASS',casos:e.casos,fecha:e.fecha,grupos:e.grupos.map(g=>({empresa:g.empresa,moneda:g.moneda})),produccion_modificada:false},null,2))
  console.log('PASS ENSAYO AUTENTICADO FINAL: '+e.casos.length+' comprobaciones')
}

export async function revisionapp(){
  assert.equal(e.resultado,'PASS')
  for(const g of e.grupos){
    const s=await llamada('solicitud_inversion_fn',{p_solicitud:g.pendiente})
    const nueva=JSON.parse(sql(`select to_jsonb(c) from crm.inversiones i join crm.cierres_externos c on c.id=i.cierre_externo_id where i.id=${q(s.inversion_id)}`))
    await correccion(g,g.fuente,'calendario',12);await correccion(g,nueva.id,'dias_360',12)
    registrar(`${g.empresa} ${g.moneda}: revisión obtenida por la RPC real de Gerencia`)
  }
  writeFileSync(dir+'/resultado-api.json',JSON.stringify({resultado:'PASS',casos:e.casos,fecha:e.fecha,grupos:e.grupos.map(g=>({empresa:g.empresa,moneda:g.moneda})),produccion_modificada:false},null,2))
  console.log('PASS RUTA REAL DE REVISION: '+e.casos.length+' comprobaciones totales')
}
