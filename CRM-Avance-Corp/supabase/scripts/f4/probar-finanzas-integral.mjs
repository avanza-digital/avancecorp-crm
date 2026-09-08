import assert from 'node:assert/strict';
import {randomUUID,randomInt,createHash} from 'node:crypto';
import {readFileSync,writeFileSync} from 'node:fs';
import {crearCopiaSql} from './copia-sql-local.mjs';
import {entorno,leer,sql as originalSql,literal as q} from './banco-local.mjs';
import {contratoPrueba} from './operaciones-fixture.mjs';
const f=leer('fixtures.json'),base=leer('operaciones-base.json'),g=f.usuarios.gerencia.id,v=f.usuarios.vendedor.id,ajeno=f.usuarios.ajeno.id;
assert.equal(entorno,'avancecorp-f4-reconstruccion');
const copia=crearCopiaSql('finanzas_integral',{baseOrigen:leer('respaldo-pre-f4.json').nombre}),{sql}=copia,pruebas=[];
const {archivo}=JSON.parse(readFileSync(new URL('./ultima-migracion.json',import.meta.url),'utf8'));
sql(readFileSync(new URL(`../../migrations/${archivo}`,import.meta.url),'utf8'),{admin:true});
const j=x=>q(JSON.stringify(x)),claims=a=>`set local request.jwt.claims=${j({sub:a,role:'authenticated'})};set local role authenticated;`;
const llamada=(fn,args,schema='crm')=>`select ${schema}.${fn}(${args.join(',')})`;
const como=(consulta,a=g)=>sql(`\\set VERBOSITY verbose
begin;set local statement_timeout='20s';${claims(a)}${consulta};commit;`);
const rpc=(fn,args,schema='crm')=>JSON.parse(como(llamada(fn,args,schema)));
const cap=(filtro='true')=>JSON.parse(sql(`select coalesce(jsonb_agg(to_jsonb(k) order by to_jsonb(k)::text),'[]') from private.capital_episodios('-infinity','infinity',true,'{}') k where ${filtro}`));
const conv=(periodo,perfil)=>JSON.parse(sql(`select coalesce(jsonb_agg(to_jsonb(c) order by to_jsonb(c)::text),'[]') from private.conversion_episodios(
 ${q(periodo)}::timestamp at time zone 'America/Lima',(${q(periodo)}::date+interval '1 month')::timestamp at time zone 'America/Lima',${q(periodo)},true,'{}',0.15) c
 where operacion_id in (select id from crm.operaciones_cartera where cliente_id=${q(perfil)})`));
const fotoSql=`select private.idem_hash(jsonb_build_object('c',(select jsonb_agg(to_jsonb(c) order by id) from public.contratos c),
 'e',(select jsonb_agg(to_jsonb(e) order by id) from crm.cierres_externos e),'p',(select jsonb_agg(to_jsonb(p) order by periodo) from crm.periodos_cerrados p)))`;
const original=originalSql(fotoSql);
function caso(nombre,fn){fn();pruebas.push({nombre,conforme:true});console.log('PASS: '+nombre);}
function perfil(){const id=randomUUID(),doc=String(randomInt(93000000,98999999));
 sql(`insert into auth.users(id) values(${q(id)});insert into public.perfiles(id,nombre_completo,rol,tipo_documento,dni,activo,asesor_perfil_id,domicilio,correo)
 values(${q(id)},'CLIENTE FICTICIO DE FINANZAS','cliente','DNI',${q(doc)},true,${q(v)},'CALLE FICTICIA 123, LIMA',${q(`finanzas-${id}@example.test`)});`);return id;}
function contrato(cliente,{categoria='nuevo',inicio='2026-09-01',capital=1000,moneda='PEN',origen=null,renovado=1000,adicional=0}={}){
 const d=contratoPrueba(cliente,v,{categoria,inicio,capital,moneda});
 if(origen) Object.assign(d.contrato,{contrato_origen_id:origen,capital_renovado:renovado,capital_adicional:adicional});
 const persona=sql(`select id from crm.inversionistas where perfil_id=${q(cliente)} and estado='activo'`);
 if(!persona) return rpc('crear_contrato_con_cuenta_pdf_v2',[j(d.contrato),j(d.cronograma),j(d.cuenta)]);
 const id=randomUUID();rpc('preparar_inversion_fn',[q(id),j({inversionista_id:persona,empresa:'avance',...d})]);
 return rpc('confirmar_inversion_fn',[q(id)]).fuente;
}
function coop(persona,fecha='2026-09-01',monto=333){const id=randomUUID(),datos={inversionista_id:persona,empresa:'qorilazo',monto,moneda:'PEN',fecha_comercial:fecha,
 vence_en:'2027-09-01',numero_transaccion:'F4-FIN-'+id,referencia:'FINANZAS FICTICIAS',evidencia:{ruta:`${persona}/${id}/p.png`}};
 rpc('preparar_inversion_fn',[q(id),j(datos)]);sql(`insert into storage.objects(bucket_id,name,metadata) values('f4-comprobantes',${q(datos.evidencia.ruta)},'{"size":12,"mimetype":"image/png"}')`);
 return {id,datos,confirmar:()=>rpc('confirmar_inversion_fn',[q(id)])};}
function lead(){const id=randomUUID();sql(`insert into crm.leads(id,nombre_completo,telefono,monto_estimado,etapa,vendedor_id,creado_por,origen)
 values(${q(id)},'LEAD FICTICIO FINANZAS',${q('986'+String(randomInt(1e6)).padStart(6,'0'))},1000,'propuesta_enviada',${q(v)},${q(v)},'landing')`);return id;}
const sello=periodo=>sql(`select private.idem_hash(jsonb_build_object('p',(select to_jsonb(p) from crm.periodos_cerrados p where periodo=${q(periodo)}),
 'v',(select jsonb_agg(to_jsonb(v) order by vendedor_id) from crm.cierre_mes_vendedor v where periodo=${q(periodo)})))`);
try{
 assert.equal(sql("select count(*) from crm.periodos_cerrados where periodo>='2026-06-01'"),'0','Este ensayo parte de la reconstrucción sin sellos junio/julio');
 sql("update crm.multiempresa_flags set activo=true where nombre='inversiones_escritura'");
 sql(`update public.perfiles set telefono='999111222' where id=${q(g)} and telefono is null`);
 const p=perfil(),origen=contrato(p,{inicio:'2025-08-01'}),ren=contrato(p,{categoria:'renovacion',inicio:'2026-08-01',capital:1200,origen:origen.id,adicional:200});
 caso('Renovación F4 mantiene peso 0.15, divisor cero y desglose sin duplicar stock',()=>{
  const c=conv('2026-08-01',p);assert.equal(c.length,1);assert.equal(c[0].aporte_numerador,0.15);assert.equal(c[0].aporte_divisor,0);
  const k=cap(`contrato_id=${q(ren.id)}`);assert.equal(k.find(x=>x.medida==='stock').monto,1200);
  assert.equal(k.find(x=>x.tipo==='desglose_renovado').monto,1000);assert.equal(k.find(x=>x.tipo==='desglose_adicional').monto,200);
  assert.equal(sql(`select estado from public.contratos where id=${q(origen.id)}`),'renovado');
 });
 const segunda=contrato(p,{categoria:'upgrade',inicio:'2026-08-15',capital:500});
 caso('Segunda operación del cliente/mes conserva capital sin otro aporte de conversión',()=>{
  assert.equal(conv('2026-08-01',p).length,1);assert.equal(cap(`contrato_id=${q(segunda.id)} and medida='stock'`)[0].monto,500);
 });
 caso('Rango parcial no promueve la segunda operación del mes',()=>{
  assert.equal(sql(`select count(*) from private.conversion_episodios('2026-08-15 00:00-05','2026-09-01 00:00-05',null,true,'{}',0.15)
   where operacion_id in (select id from crm.operaciones_cartera where cliente_id=${q(p)})`),'0');
 });
 const usd=contrato(p,{moneda:'USD',capital:1500});
 caso('PEN y USD siguen separados y cada fuente tiene una sola inversión',()=>{
  assert.equal(cap(`contrato_id=${q(usd.id)} and medida='stock'`)[0].moneda,'USD');
  for(const c of [origen,ren,segunda,usd])assert.equal(sql(`select count(*) from crm.inversiones where contrato_id=${q(c.id)}`),'1');
 });
 const pa=perfil(),la=lead();rpc('convertir_lead',[q(la),q(pa)]);const ca=contrato(pa);
 const ia=sql(`select id from crm.inversionistas where perfil_id=${q(pa)}`),extra=coop(ia).confirmar();
 const antesAnular=cap(`contrato_id=${q(ca.id)} or cierre_externo_id=${q(extra.fuente.cierre_id)}`);
 caso('Anular conversión inicial Avance con inversión cooperativa adicional conserva Capital',()=>{
  rpc('anular_cierre_avance',[q(la),"'Anulación comercial ficticia del ensayo integral'"]);
  assert.equal(sql(`select private.cierre_anulado(${q(la)})`),'t');
  assert.deepEqual(cap(`contrato_id=${q(ca.id)} or cierre_externo_id=${q(extra.fuente.cierre_id)}`),antesAnular);
  assert.equal(sql(`select estado from crm.inversiones where id=${q(extra.inversion_id)}`),'vigente');
 });
 const lc=lead(),dni=String(randomInt(93000000,98999999));
 const inicial=rpc('convertir_lead_externo',[q(lc),"'qorilazo'",1000,"'PEN'","'DNI'",q(dni),"'PERSONA FICTICIA COOPERATIVA'",q('F4-INI-'+lc),"'FICTICIO'","'2027-09-01'","'Ensayo financiero sintético'"]);
 const ic=sql(`select inversionista_id from crm.leads where id=${q(lc)}`),cie=sql(`select id from crm.cierres_externos where lead_id=${q(lc)} and es_cierre_inicial`);
 const adicional=coop(ic).confirmar();
 caso('Anular cierre inicial cooperativo reduce conversión sin borrar su capital ni la inversión posterior',()=>{
  const antes=cap(`lead_id=${q(lc)}`).reduce((a,k)=>a+(k.medida==='stock'?k.monto:0),0);assert.equal(antes,1333);
  rpc('anular_cierre_externo',[q(cie),"'Anulación comercial ficticia del cierre inicial'"]);
  assert.equal(sql(`select private.cierre_anulado(${q(lc)})`),'t');
  assert.equal(cap(`lead_id=${q(lc)}`).reduce((a,k)=>a+(k.medida==='stock'?k.monto:0),0),antes);
  assert.equal(sql(`select estado from crm.inversiones where cierre_externo_id=${q(cie)}`),'anulada');
  assert.equal(sql(`select estado from crm.inversiones where id=${q(adicional.inversion_id)}`),'vigente');
  assert.equal(sql(`select coalesce(sum(aporte_numerador),0) from private.conversion_episodios('2026-09-01 00:00-05','2026-10-01 00:00-05','2026-09-01',true,'{}',0.15) where lead_id=${q(lc)}`),'0');
 });
 caso('Contrato demo conserva registro pero no participa del Capital real ni del censo histórico',()=>{
  rpc('marcar_contrato_demo',[q(usd.id),'true',"'Contrato sintético clasificado como demo'"],'public');
  assert.deepEqual(cap(`contrato_id=${q(usd.id)}`),[]);
  assert.equal(JSON.parse(sql(`select private.inversion_historica_estado('contrato',${q(usd.id)})`)).estado,'excluido_demo');
 });
 // Línea de upgrade vencida que puede renovarse hoy: no se altera el reloj ni
 // el estado del contrato para saltar la condición de vencimiento.
 const pc=perfil();contrato(pc,{inicio:'2025-05-01'});
 const cabeza=contrato(pc,{categoria:'upgrade',inicio:'2025-06-01',capital:700});
 const hija=contrato(pc,{categoria:'renovacion',inicio:'2026-06-01',capital:800,origen:cabeza.id,renovado:700,adicional:100});
 const autorOriginal=sql(`select creado_por from public.contratos where id=${q(cabeza.id)}`);
 async function carrera(nombre,aSql,bSql){
  const a=copia.abrirSesion('f4_fin_primero'),b=copia.abrirSesion('f4_fin_segundo');
  a.enviar(`begin;set local statement_timeout='20s';${claims(g)}${aSql};select 'BARRERA';`);
  await copia.esperar(()=>a.salida().includes('BARRERA'),'No se completó la primera operación financiera');
  b.enviar(`begin;set local statement_timeout='20s';${claims(g)}${bSql};select 'SEGUNDO_LISTO';`);
  await copia.esperar(()=>sql("select count(*) from pg_stat_activity where datname=current_database() and application_name='f4_fin_segundo' and wait_event_type='Lock'")==='1','El segundo escritor no esperó el sello');
  assert.equal((await a.cerrar('commit;')).codigo,0);
  await copia.esperar(()=>b.salida().includes('SEGUNDO_LISTO'),'El segundo escritor no terminó tras liberar el período');
  const r=await b.cerrar('commit;');assert.equal(r.codigo,0,r.error);pruebas.push({nombre,conforme:true});console.log('PASS: '+nombre);
 }
 const jun=coop(base.identidades.qorilazo,'2026-06-15',425);
 await carrera('Alta gana al sello: junio incluye la inversión confirmada antes del cierre',llamada('confirmar_inversion_fn',[q(jun.id)]),llamada('cerrar_periodo',["'2026-06-01'"]));
 caso('Alta anterior al sello no crea ajuste tardío y conserva fecha comercial junio',()=>{
  assert.equal(sql(`select c.fecha_imputacion from crm.inversion_solicitudes s join crm.inversiones i on i.id=s.inversion_id join crm.cierres_externos c on c.id=i.cierre_externo_id where s.id=${q(jun.id)}`),'2026-06-15');
  assert.equal(sql(`select count(*) from crm.inversion_ajustes_mes_cerrado a join crm.inversion_solicitudes s on s.inversion_id=a.inversion_id where s.id=${q(jun.id)}`),'0');
 });
 const selloJun=sello('2026-06-01');
 caso('Reasignación real de cabeza mueve atribución viva de su renovación sin tocar autor ni mes sellado',()=>{
  rpc('reasignar_analista_contrato',[q(cabeza.id),q(ajeno),"'Reasignación ficticia de la cabeza de una línea de upgrade'"],'public');
  assert.equal(cap(`contrato_id=${q(hija.id)} and medida='stock'`)[0].analista_id,ajeno);
  assert.equal(sql(`select creado_por from public.contratos where id=${q(cabeza.id)}`),autorOriginal);
  assert.equal(sello('2026-06-01'),selloJun);
 });
 const jul=coop(base.identidades.qorilazo,'2026-07-15',526);
 await carrera('Sello gana al alta: julio se congela y el alta espera su resultado',llamada('cerrar_periodo',["'2026-07-01'"]),llamada('confirmar_inversion_fn',[q(jul.id)]));
 caso('Alta posterior conserva julio comercial, imputa al mes vivo y deja ajuste único',()=>{
  const c=JSON.parse(sql(`select to_jsonb(c) from crm.inversion_solicitudes s join crm.inversiones i on i.id=s.inversion_id join crm.cierres_externos c on c.id=i.cierre_externo_id where s.id=${q(jul.id)}`));
  assert.equal(c.fecha_comercial,'2026-07-15');assert.equal(c.fecha_imputacion,sql("select (now() at time zone 'America/Lima')::date"));
  assert.equal(sql(`select count(*) from crm.inversion_ajustes_mes_cerrado a join crm.inversion_solicitudes s on s.inversion_id=a.inversion_id where s.id=${q(jul.id)}`),'1');
  const antes=sello('2026-07-01');jul.confirmar();assert.equal(sello('2026-07-01'),antes);assert.equal(sello('2026-06-01'),selloJun);
 });
 caso('Fecha lejana en mes abierto conserva imputación declarada sin modificar sellos existentes',()=>{
  const antesJun=sello('2026-06-01'),antesJul=sello('2026-07-01');
  const informeJun=rpc('cumplimiento_metas_fn',["'2026-06-01'"]);
  const ajustes=sql("select private.idem_hash(coalesce(jsonb_agg(to_jsonb(a) order by id),'[]')) from crm.ajustes_mes_cerrado a");
  assert.equal(sql("select count(*) from crm.periodos_cerrados where periodo='2001-01-01'"),'0');
  const antigua=coop(base.identidades.qorilazo,'2001-01-15',777),resultado=antigua.confirmar();
  const cierre=JSON.parse(sql(`select to_jsonb(c) from crm.cierres_externos c where id=${q(resultado.fuente.cierre_id)}`));
  assert.equal(cierre.fecha_comercial,'2001-01-15');assert.equal(cierre.fecha_imputacion,'2001-01-15');
  assert.equal(sql(`select count(*) from crm.inversion_ajustes_mes_cerrado where inversion_id=${q(resultado.inversion_id)}`),'0');
  assert.equal(cap(`cierre_externo_id=${q(resultado.fuente.cierre_id)} and medida='stock'`)[0].monto,777);
  assert.equal(sello('2026-06-01'),antesJun);assert.equal(sello('2026-07-01'),antesJul);
  assert.deepEqual(rpc('cumplimiento_metas_fn',["'2026-06-01'"]),informeJun);
  assert.equal(sql("select private.idem_hash(coalesce(jsonb_agg(to_jsonb(a) order by id),'[]')) from crm.ajustes_mes_cerrado a"),ajustes);
 });
}finally{assert.equal(originalSql(fotoSql),original);}
writeFileSync(new URL(`../evidencia-f4/finanzas-integral-${copia.id}.json`,import.meta.url),JSON.stringify({entorno,baseCopia:copia.nombre,terminadoEn:new Date().toISOString(),pruebas,
 bancoOriginalSinCambios:true,sha256Oraculo:createHash('sha256').update(readFileSync(new URL(import.meta.url))).digest('hex'),
 limites:['Fixtures SQL explícitas para perfiles/leads y metadatos Storage; operaciones, renovaciones, anulación, atribución y sellado mediante RPC reales.',
 'No se encontró registro de comisiones pagadas en este esquema; su ubicación se consultó al usuario. Este oráculo no simula ni afirma liquidación de comisiones.'],
},null,2)+'\n',{flag:'wx'});
console.log(`Finanzas integrales: ${pruebas.length} grupos conformes.`);
