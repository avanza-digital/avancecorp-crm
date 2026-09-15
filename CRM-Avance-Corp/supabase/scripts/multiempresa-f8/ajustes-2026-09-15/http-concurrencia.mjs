import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
// Evidencia del ensayo: requiere el directorio privado del banco autorizado.
const dir=process.env.F8_EVIDENCIA_PRIVADA;
assert.ok(dir?.endsWith('/'), 'Falta F8_EVIDENCIA_PRIVADA con barra final');
const cfg=JSON.parse(readFileSync(dir+'rama-privada.json','utf8'));
const grupo=JSON.parse(readFileSync(dir+'http-miembros.json','utf8'));
const tokens=JSON.parse(readFileSync(dir+'http-sesiones.json','utf8'));
assert.equal(cfg.SUPABASE_URL,'https://hqazubfaznppkfelctej.supabase.co');
const actor=grupo.analistas[0].id,ajeno=grupo.analistas[1].id;
const lead='a501a318-6072-4348-a86f-bd398751c750';
const solicitud='a501a318-6072-4348-a86f-bd398751c751';
const correccion='a501a318-6072-4348-a86f-bd398751c752';
const recibo={peticiones:[],inicioUTC:new Date().toISOString(),casos:[]};
const info=JSON.parse(readFileSync(dir+'http-fixture-info.json','utf8'));
const password=readFileSync(dir+'auth-fixture-password.txt','utf8');
for(const uid of [actor,ajeno,grupo.supervisor.id,grupo.gerencia.id]) {
 const claims=JSON.parse(Buffer.from(tokens[uid].split('.')[1],'base64url'));
 if(claims.exp>Date.now()/1000+300)continue;
 const user=info.actores.find(x=>x.id===uid);
 const r=await fetch(cfg.SUPABASE_URL+'/auth/v1/token?grant_type=password',{method:'POST',headers:{apikey:cfg.SUPABASE_ANON_KEY,'Content-Type':'application/json'},body:JSON.stringify({email:user.email,password}),signal:AbortSignal.timeout(30000)});
 assert.equal(r.status,200,'Renovación de sesión sintética');const b=await r.json();assert.equal(b.user.id,uid);tokens[uid]=b.access_token;
}
writeFileSync(dir+'http-sesiones.json',JSON.stringify(tokens),{mode:0o600});
const headers=uid=>({apikey:cfg.SUPABASE_ANON_KEY,Authorization:'Bearer '+tokens[uid]});
async function rpc(name,body,uid=actor){
 console.log('RPC',name);const inicioPeticion=Date.now();
 const r=await fetch(cfg.SUPABASE_URL+'/rest/v1/rpc/'+name,{method:'POST',
  headers:{...headers(uid),'Content-Type':'application/json','Content-Profile':'crm'},body:JSON.stringify(body),signal:AbortSignal.timeout(20000)});
 const bodyResult=await r.json();recibo.peticiones.push({rpc:name,status:r.status,codigo:bodyResult?.code??null,ms:Date.now()-inicioPeticion});return {status:r.status,body:bodyResult};
}
function ok(label,r){assert.equal(r.status,200,label+': '+JSON.stringify(r.body));recibo.casos.push(label);console.log('PASS',label);return r.body;}
function rechazo(label,r,code){assert.ok(r.status>=400,label);assert.equal(r.body.code,code,label);recibo.casos.push(label);}
const inicial={p_lead_id:lead,p_cooperativa:'qorilazo',p_monto:1000,p_moneda:'PEN',
 p_documento_tipo:'DNI',p_documento:'79999764',p_nombre:'PRUEBA HTTP CONCURRENTE F8',
 p_numero_transaccion:'F8-HTTP-CONCURRENTE-INICIAL',p_referencia:'Certificado sintético',p_plazo_meses:12,p_tasa_anual:12};
const primero=ok('alta inicial con 12% anual',await rpc('convertir_lead_externo',inicial));
const reintento=ok('reintento inicial',await rpc('convertir_lead_externo',inicial));
assert.equal(reintento.reintento,true);assert.equal(primero.cierre_id,reintento.cierre_id);
rechazo('cambio de tasa en reintento rechazado',await rpc('convertir_lead_externo',{...inicial,p_tasa_anual:13}),'P0409');
const cartera=ok('identidad resuelta por Cartera',await rpc('cartera_inversionistas_fn',{p_texto:'PRUEBA HTTP CONCURRENTE F8'}));
assert.equal(cartera.filas.length,1);const persona=cartera.filas[0].inversionista_id??cartera.filas[0].id;assert.ok(persona);
const fichaInicial=ok('ficha inicial desde núcleo',await rpc('inversionista_ficha_fn',{p_inversionista:persona}));
assert.equal(fichaInicial.inversiones_total,1);
const inversionInicial=fichaInicial.inversiones[0];
assert.deepEqual(inversionInicial.condiciones_coopac,{plazo_meses:12,tasa_anual:12});
const inicio=new Intl.DateTimeFormat('sv-SE',{timeZone:'America/Lima'}).format(new Date());
const [year,month,day]=inicio.split('-').map(Number);
const fin=new Date(Date.UTC(year+1,month-1,Math.min(day,new Date(Date.UTC(year+1,month,0)).getUTCDate()))).toISOString().slice(0,10);
assert.equal(inversionInicial.vence_en,fin);recibo.inicial={inicio,vence:fin,plazo:12,tasa:12};

// PDF mínimo válido, generado exclusivamente para este banco.
const contenido='BT /F1 12 Tf 30 100 Td (COMPROBANTE SINTETICO F8) Tj ET';
const objetos=['<</Type /Catalog /Pages 2 0 R>>','<</Type /Pages /Kids [3 0 R] /Count 1>>',
 '<</Type /Page /Parent 2 0 R /MediaBox [0 0 300 160] /Contents 4 0 R /Resources <</Font <</F1 5 0 R>>>>>>',
 `<</Length ${Buffer.byteLength(contenido)}>>\nstream\n${contenido}\nendstream`,'<</Type /Font /Subtype /Type1 /BaseFont /Helvetica>>'];
let pdf='%PDF-1.4\n';const offsets=[0];
for(const [i,o] of objetos.entries()){offsets.push(Buffer.byteLength(pdf));pdf+=`${i+1} 0 obj\n${o}\nendobj\n`;}
const start=Buffer.byteLength(pdf);pdf+='xref\n0 6\n0000000000 65535 f \n'+offsets.slice(1).map(n=>String(n).padStart(10,'0')+' 00000 n \n').join('');
pdf+=`trailer\n<</Size 6 /Root 1 0 R>>\nstartxref\n${start}\n%%EOF\n`;
const bytes=Buffer.from(pdf),ruta=persona+'/'+solicitud+'/comprobante.pdf';
const datos={inversionista_id:persona,empresa:'prodelco',monto:2500,moneda:'PEN',fecha_comercial:'2024-02-29',
 vence_en:'2025-02-28',plazo_meses:12,tasa_anual:12,numero_transaccion:'F8-HTTP-CONCURRENTE-ADICIONAL',referencia:'Certificado adicional sintético',evidencia:{ruta}};
ok('preparación adicional',await rpc('preparar_inversion_fn',{p_clave:solicitud,p_datos:datos}));
console.log('STORAGE subida');
const carga=await fetch(cfg.SUPABASE_URL+'/storage/v1/object/f4-comprobantes/'+ruta,{method:'POST',headers:{...headers(actor),'Content-Type':'application/pdf','x-upsert':'false'},body:bytes,signal:AbortSignal.timeout(20000)});
const cargaBody=await carga.json();
if(carga.status===200)recibo.casos.push('comprobante sintético subido como analista');
else {
 assert.equal(cargaBody.code,'KeyAlreadyExists','Subida: '+JSON.stringify(cargaBody));
 const existente=await fetch(cfg.SUPABASE_URL+'/storage/v1/object/authenticated/f4-comprobantes/'+ruta,{headers:headers(actor),signal:AbortSignal.timeout(30000)});
 assert.equal(existente.status,200);assert.deepEqual(Buffer.from(await existente.arrayBuffer()),bytes);
 recibo.casos.push('reintento: comprobante previamente subido idéntico');
}
rechazo('corrección de empresa rechazada',await rpc('corregir_solicitud_inversion_fn',{p_solicitud:solicitud,p_clave:'a501a318-6072-4348-a86f-bd398751c754',p_revision_datos_esperada:0,p_datos:{...datos,empresa:'qorilazo'},p_motivo:'Intento de cambiar empresa en solicitud'}),'22023');
ok('corrección de plazo y tasa anual',await rpc('corregir_solicitud_inversion_fn',{p_solicitud:solicitud,p_clave:correccion,p_revision_datos_esperada:0,
 p_datos:{...datos,plazo_meses:6,tasa_anual:12.5,vence_en:'2024-08-29'},p_motivo:'Plazo y porcentaje pactados corregidos en prueba'}));
rechazo('corrección con revisión anterior rechazada',await rpc('corregir_solicitud_inversion_fn',{p_solicitud:solicitud,p_clave:'a501a318-6072-4348-a86f-bd398751c753',p_revision_datos_esperada:0,p_datos:{...datos,plazo_meses:6,tasa_anual:12.5,vence_en:'2024-08-29'},p_motivo:'Reintento desde una pestaña desactualizada'}),'PT409');
rechazo('revisión anterior rechazada',await rpc('confirmar_inversion_revisada_fn',{p_solicitud:solicitud,p_revision_datos_esperada:0}),'PT409');
const simultaneas=await Promise.all([rpc('confirmar_inversion_revisada_fn',{p_solicitud:solicitud,p_revision_datos_esperada:1}),rpc('confirmar_inversion_revisada_fn',{p_solicitud:solicitud,p_revision_datos_esperada:1})]);
const dos=simultaneas.map((r,i)=>ok('confirmación concurrente '+i,r));assert.equal(dos.filter(r=>r.reintento===true).length,1);assert.ok(dos[0].inversion_id);assert.equal(dos[0].inversion_id,dos[1].inversion_id);
const otraVez=ok('reintento adicional',await rpc('confirmar_inversion_revisada_fn',{p_solicitud:solicitud,p_revision_datos_esperada:1}));
assert.equal(otraVez.reintento,true);
rechazo('otro analista no confirma',await rpc('confirmar_inversion_revisada_fn',{p_solicitud:solicitud,p_revision_datos_esperada:1},ajeno),'42501');
for(const uid of [actor,grupo.supervisor.id,grupo.gerencia.id]){
 const f=ok('ficha con condiciones por rol '+uid,await rpc('inversionista_ficha_fn',{p_inversionista:persona},uid));
 assert.equal(f.inversiones_total,2);const inversion=f.inversiones.find(i=>i.empresa==='prodelco');
 assert.deepEqual(inversion.condiciones_coopac,{plazo_meses:6,tasa_anual:12.5});assert.equal(inversion.vence_en,'2024-08-29');
 assert.equal(f.continuidad.proximo_vencimiento,'2024-08-29');
}
console.log('STORAGE descarga');
const descarga=await fetch(cfg.SUPABASE_URL+'/storage/v1/object/authenticated/f4-comprobantes/'+ruta,{headers:headers(actor),signal:AbortSignal.timeout(20000)});
assert.equal(descarga.status,200);assert.deepEqual(Buffer.from(await descarga.arrayBuffer()),bytes);recibo.casos.push('descarga íntegra del comprobante');
const indebida=await fetch(cfg.SUPABASE_URL+'/storage/v1/object/authenticated/f4-comprobantes/'+ruta,{headers:headers(ajeno),signal:AbortSignal.timeout(20000)});
assert.ok(indebida.status>=400);recibo.casos.push('comprobante ajeno bloqueado');
recibo.resultado='PASS';recibo.comprobante={bytes:bytes.length,sha256:createHash('sha256').update(bytes).digest('hex')};
recibo.adicional={plazo:6,tasa:12.5,vence:'2024-08-29'};
writeFileSync(dir+'http-concurrencia.json',JSON.stringify(recibo,null,2),{mode:0o600});
console.log(`PASS ${recibo.casos.length} casos HTTP de COOPAC, correcciones, reintentos, roles y comprobante`);
