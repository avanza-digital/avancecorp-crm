// SQL financiero sintético. Destino fijo, sin URL, JWT ni credenciales remotas.
// La copia se prepara fuera de este ejecutor: jamás recrea ni modifica la fuente.
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {randomUUID,randomInt,createHash} from 'node:crypto';
import {readFileSync,writeFileSync} from 'node:fs';
const contenedor='supabase_db_avancecorp-f5-bank',db='g7_cierre_20260915';
const prefijo='g7_'+randomUUID().slice(0,8),resultados=[];
const inicio=new Date().toISOString();
// Un fallo de precondición no puede dejar como vigente el PASS de otra ejecución.
writeFileSync(new URL('ensayo-local.json',import.meta.url),JSON.stringify({estado:'RUNNING',inicio,banco:db})+'\n');
const q=x=>`'${String(x).replaceAll("'","''")}'`;
const j=x=>q(JSON.stringify(x))+'::jsonb';
const args=['exec','-i',contenedor,'psql','-X','-qAt','-U','postgres','-d',db,'-v','ON_ERROR_STOP=1','-f','-'];
const cabecera="\\set VERBOSITY verbose\nset timezone='America/Lima'; set statement_timeout='20s';\n";
function ejecutar(s) {return spawnSync('docker',args,{input:cabecera+s,encoding:'utf8',maxBuffer:8*1024*1024});}
function sql(s) {const r=ejecutar(s);assert.equal(r.status,0,r.stderr||r.error?.message);return r.stdout.trim();}
const objeto=s=>JSON.parse(sql(s));
const claims=actor=>`set local role authenticated;set local request.jwt.claim.sub=${q(actor)};`;
const tx=(actor,s)=>`begin;${claims(actor)} select ${s};commit;`;
const llamada=(fn,vals)=>`${fn}(${vals.join(',')})`;
function rpc(fn,vals,actor) {
  const r=ejecutar(tx(actor,llamada(fn,vals)));
  if(r.status!==0)return {ok:false,codigo:r.stderr.match(/ERROR:\s+([A-Z0-9]{5}):/)?.[1],error:r.stderr};
  return {ok:true,data:JSON.parse(r.stdout.trim())};
}
const ok=r=>{assert.ok(r.ok,r.error);return r.data;};
const rechazo=(r,codes)=>{assert.equal(r.ok,false);assert.ok(codes.includes(r.codigo),r.error);};
const pausa=ms=>new Promise(r=>setTimeout(r,ms));
async function esperar(fn,msg) {for(let i=0;i<100;i++){if(fn())return;await pausa(50);}throw new Error(msg);}
function proceso(s) {
  const p=spawn('docker',args);let out='',err='';
  p.stdout.setEncoding('utf8');p.stderr.setEncoding('utf8');
  p.stdout.on('data',x=>{out+=x;});p.stderr.on('data',x=>{err+=x;});
  const termina=new Promise(resolve=>p.on('close',status=>resolve({status,out,err})));
  p.stdin.write(cabecera+s);return {p,termina,salida:()=>out};
}
async function carrera(label,consultas,actor) {
  // Retiene F4 para observar dos sesiones reales esperando el mismo candado.
  const h=proceso("begin;select pg_advisory_xact_lock(hashtext('crm_flag_inversiones_escritura'));select 'G7_LISTO';\n");
  const ps=[];let observadas=0;
  try {
    await esperar(()=>h.salida().includes('G7_LISTO'),'No llegó la barrera G7');
    for(const [i,c] of consultas.entries()) {
      const p=proceso(`set application_name=${q(prefijo+'_'+i)};${tx(actor,c)}\n`);
      p.p.stdin.end();ps.push(p);
    }
    await esperar(()=>{
      observadas=Number(sql(`select count(*) from pg_stat_activity where datname=current_database()
        and application_name in(${consultas.map((_,i)=>q(prefijo+'_'+i)).join(',')}) and wait_event_type='Lock'`));
      return observadas===consultas.length;
    },'No se observó coincidencia SQL: '+label);
  } finally {h.p.stdin.end('rollback;\n');await h.termina;}
  const respuestas=await Promise.all(ps.map(async p=>{
    const r=await p.termina;return r.status===0?{ok:true,data:JSON.parse(r.out.trim())}:
      {ok:false,codigo:r.err.match(/ERROR:\s+([A-Z0-9]{5}):/)?.[1],error:r.err};
  }));
  resultados.push({caso:label,sesiones_coincidentes:observadas,codigos:respuestas.map(x=>x.ok?'OK':x.codigo)});
  return respuestas;
}
const firmasQuery="select jsonb_agg(jsonb_build_object('firma',p.oid::regprocedure::text,'huella',md5(pg_get_functiondef(p.oid))) order by p.oid::regprocedure::text) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in('crm','private') and p.proname ~ '(inversion|coopac|piloto|rol_crm|es_lector|cartera_f5|puede_gestionar_contratos)'";
const productivas=JSON.parse(readFileSync(new URL('versiones-nucleo.json',import.meta.url),'utf8'));
const funciones=objeto(firmasQuery);
assert.equal(funciones.length,65);
assert.deepEqual(funciones,productivas,'Deriva de las funciones financieras y de permisos seleccionadas');
assert.equal(sql('select current_database()'),db);
const miembros=objeto(`select jsonb_agg(jsonb_build_object('id',m.perfil_id,'rol',m.rol_esperado)
  order by m.rol_esperado,m.perfil_id) from crm.piloto_f8_miembros m
  join crm.equipo e on e.perfil_id=m.perfil_id and e.activo
  join public.perfiles p on p.id=m.perfil_id and p.activo`);
assert.equal(miembros.length,4);
const actor=miembros.find(x=>x.rol==='vendedor').id;
const flagsAntes=objeto('select jsonb_object_agg(nombre,activo) from crm.multiempresa_flags');
function configurarPiloto() {
  sql(`begin;update crm.piloto_f8_control set activo=false where singleton;
    update crm.multiempresa_flags set activo=(nombre='resolver_en_puertas');
    update crm.piloto_f8_miembros set activo=true;
    update crm.piloto_f8_control set activo=true,motivo='Ensayo económico local G7 con datos ficticios' where singleton;
    commit;`);
  assert.equal(sql('select private.piloto_f8_modo_activo()'),'t');
}
function personaNueva(n) {
  const lead=randomUUID(),doc=String(randomInt(88000000,89999999));
  const deposito=prefijo+'-INICIAL-'+n;
  sql(`insert into crm.leads(id,nombre_completo,telefono,monto_estimado,vendedor_id,creado_por)
    values(${q(lead)},${q('PERSONA SINTETICA G7 '+n)},${q('+519'+String(randomInt(10000000,99999999)))},1000,${q(actor)},${q(actor)})`);
  const expresion=llamada('crm.convertir_lead_externo',[q(lead),q('qorilazo'),1000,q('PEN'),q('DNI'),q(doc),
    q('PERSONA SINTETICA G7 '+n),q(deposito),q('CONSTANCIA FICTICIA'),"null","null",12,12]);
  return {lead,deposito,expresion};
}
function ejecutarExpresion(expresion) {
  const r=ejecutar(tx(actor,expresion));assert.equal(r.status,0,r.stderr);return JSON.parse(r.stdout.trim());
}
const fecha=sql("select (now() at time zone 'America/Lima')::date");
const vence=sql(`select private.coopac_validar_condiciones(${q(fecha)},12,12)`);
function solicitud(persona,empresa,deposito=prefijo+'-'+randomUUID()) {
  const id=randomUUID();return {id,datos:{inversionista_id:persona,empresa,monto:123,moneda:'PEN',fecha_comercial:fecha,
    vence_en:vence,plazo_meses:12,tasa_anual:12,numero_transaccion:deposito,referencia:'ENSAYO G7 FICTICIO',
    evidencia:{ruta:persona+'/'+id+'/comprobante.pdf'}}};
}
const preparar=s=>rpc('crm.preparar_inversion_fn',[q(s.id),j(s.datos)],actor);
const confirmar=(s,rev=0)=>rpc('crm.confirmar_inversion_revisada_fn',[q(s.id),rev],actor);
const expresionConfirmar=(s,rev=0)=>llamada('crm.confirmar_inversion_revisada_fn',[q(s.id),rev]);
function lista(s) {
  ok(preparar(s));sql(`insert into storage.objects(bucket_id,name,metadata) values('f4-comprobantes',
    ${q(s.datos.evidencia.ruta)},'{"size":12,"mimetype":"application/pdf"}')`);
}
function historia(s) {return sql(`select jsonb_build_object('s',to_jsonb(s),'i',to_jsonb(i),'c',to_jsonb(c),
  'd',(select jsonb_agg(to_jsonb(d) order by id) from crm.depositos_reclamados d where d.cierre_id=c.id),
  'eventos',(select jsonb_agg(to_jsonb(e) order by id) from crm.inversion_eventos e where e.inversion_id=i.id))
  from crm.inversion_solicitudes s join crm.inversiones i on i.id=s.inversion_id
  join crm.cierres_externos c on c.id=i.cierre_externo_id where s.id=${q(s.id)}`);}
let exito=false;
try {
  configurarPiloto();
  const p1=personaNueva(1),p2=personaNueva(2);
  ejecutarExpresion(p1.expresion);ejecutarExpresion(p2.expresion);
  p1.id=sql(`select inversionista_id from crm.leads where id=${q(p1.lead)}`);
  p2.id=sql(`select inversionista_id from crm.leads where id=${q(p2.lead)}`);
  let reintentos=0;
  for(const empresa of ['qorilazo','prodelco']) {
    const s=solicitud(p1.id,empresa);lista(s);const primera=ok(confirmar(s));const antes=historia(s);
    for(let i=0;i<5;i++) {
      const r=ok(confirmar(s));assert.equal(r.reintento,true);
      const {reintento,...resto}=r;assert.deepEqual(resto,primera);
      reintentos++;assert.equal(historia(s),antes);
    }
    const lectura=ok(preparar(s));assert.equal(lectura.inversion_id,primera.inversion_id);
    assert.equal(historia(s),antes);
  }
  assert.equal(reintentos,10);resultados.push({caso:'10 reintentos confirmados, dos empresas',reintentos,historia_sin_cambios:true});

  const a=solicitud(p1.id,'qorilazo');lista(a);
  const misma=await carrera('Misma confirmación simultánea',[expresionConfirmar(a),expresionConfirmar(a)],actor);
  const dos=misma.map(ok);assert.equal(dos[0].inversion_id,dos[1].inversion_id);assert.equal(dos.filter(x=>x.reintento).length,1);
  assert.equal(sql(`select count(*) from crm.cierres_externos where numero_transaccion=upper(${q(a.datos.numero_transaccion)})`),'1');

  const dep=prefijo+'-DEPOSITO-COMPARTIDO';
  const izq=solicitud(p1.id,'qorilazo',dep),der=solicitud(p2.id,'prodelco',dep);lista(izq);lista(der);
  const dup=await carrera('Depósito simultáneo entre dos empresas y personas',[expresionConfirmar(izq),expresionConfirmar(der)],actor);
  assert.equal(dup.filter(x=>x.ok).length,1);rechazo(dup.find(x=>!x.ok),['P0409']);
  assert.equal(sql(`select count(*) from crm.depositos_reclamados where numero_norm=upper(${q(dep)})`),'1');
  assert.equal(sql(`select count(*) from crm.inversion_solicitudes where id in(${q(izq.id)},${q(der.id)}) and estado='preparada' and inversion_id is null`),'1');

  const c=solicitud(p1.id,'prodelco');
  const conflict=await carrera('Misma clave con dos importes',[llamada('crm.preparar_inversion_fn',[q(c.id),j(c.datos)]),
    llamada('crm.preparar_inversion_fn',[q(c.id),j({...c.datos,monto:124})])],actor);
  assert.equal(conflict.filter(x=>x.ok).length,1);rechazo(conflict.find(x=>!x.ok),['P0409']);
  assert.equal(sql(`select count(*) from crm.inversion_solicitudes where id=${q(c.id)}`),'1');

  const d=solicitud(p2.id,'prodelco');lista(d);const correccion=randomUUID();
  const nueva={...d.datos,monto:125};
  const corr=await carrera('Confirmar y corregir la misma revisión',[expresionConfirmar(d),
    llamada('crm.corregir_solicitud_inversion_fn',[q(d.id),q(correccion),0,j(nueva),q('Corrección económica sintética G7')])],actor);
  assert.equal(corr.filter(x=>x.ok).length,1);rechazo(corr.find(x=>!x.ok),['PT409','P0409']);
  const ds=objeto(`select jsonb_build_object('estado',estado,'revision',revision_datos,'inversion',inversion_id) from crm.inversion_solicitudes where id=${q(d.id)}`);
  if(corr[0].ok){assert.equal(ds.estado,'confirmada');assert.equal(ds.revision,0);}
  else {assert.equal(ds.estado,'preparada');assert.equal(ds.revision,1);assert.equal(ds.inversion,null);ok(confirmar(d,1));}

  const nuevaPersona=personaNueva(3);
  const altas=await carrera('Conversión inicial repetida simultáneamente',[nuevaPersona.expresion,nuevaPersona.expresion],actor);
  const altasOk=altas.map(ok);assert.equal(altasOk[0].cierre_id,altasOk[1].cierre_id);
  assert.equal(sql(`select count(*) from crm.cierres_externos where lead_id=${q(nuevaPersona.lead)}`),'1');
  assert.equal(resultados.filter(x=>x.sesiones_coincidentes===2).length,5);
  exito=true;
} finally {
  sql(`begin;update crm.piloto_f8_control set activo=false where singleton;
    update crm.piloto_f8_miembros set activo=false;
    ${Object.entries(flagsAntes).map(([nombre,activo])=>`update crm.multiempresa_flags set activo=${activo} where nombre=${q(nombre)};`).join('\n')}
    commit;`);
  const recibo={estado:exito?'PASS':'FAIL',inicio,fin:new Date().toISOString(),banco:db,funciones_verificadas:funciones.length,
    huella_funciones:createHash('sha256').update(JSON.stringify(funciones)).digest('hex'),resultados,
    limites:['SQL authenticated; no login Auth/HTTP.',
      'Metadatos Storage ficticios; no subida/descarga real de bytes.',
      'No acredita operaciones económicas reales ni firma G7.',
      'La copia conserva sus fixtures para inspección; la base fuente no se modifica.']};
  writeFileSync(new URL('ensayo-local.json',import.meta.url),JSON.stringify(recibo,null,2)+'\n');
  console.log(JSON.stringify(recibo,null,2));
}
