// Matriz SQL aislada. Las bajas usan la RPC vigente; no altera el banco original.
import assert from 'node:assert/strict';
import { createHash, randomUUID } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { crearCopiaSql } from './copia-sql-local.mjs';
import { sql as sqlOriginal, literal as q, leer } from './banco-local.mjs';
const f=leer('fixtures.json'),base=leer('operaciones-base.json');
const tablas=['public.contratos','public.cronograma_pagos','crm.cierres_externos','crm.operaciones_cartera',
 'crm.inversiones','crm.inversion_titulares','private.contrato_pdfs','crm.periodos_cerrados','crm.cierre_mes_vendedor'];
const foto=`select jsonb_object_agg(tabla,huella) from (${tablas.map(t=>`select ${q(t)} tabla,
 private.idem_hash(coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),'[]')) huella from ${t} t`).join(' union all ')}) x`;
const original=sqlOriginal(foto),copia=crearCopiaSql('permisos_dinamicos'),{sql}=copia;
assert.equal(sql(foto),original);
const pruebas=[],persona=base.identidades.avance;
const s=JSON.parse(sql(`select to_jsonb(s) from crm.inversion_solicitudes s join crm.empresas e on e.id=s.empresa_id
 where s.inversionista_id=${q(persona)} and s.estado='confirmada' and e.clave='avance' order by s.creado_en desc limit 1`));
assert(s.id);
const sesion=actor=>`set local request.jwt.claims=${q(JSON.stringify({sub:actor,role:'authenticated'}))};set local role authenticated;`;
const como=(actor,consulta,preparacion='')=>sql(`\\set VERBOSITY verbose
 begin;set local statement_timeout='15s';${preparacion}${sesion(actor)}${consulta};rollback;`);
const preparar=(id=randomUUID())=>{const datos={inversionista_id:persona,empresa:'qorilazo',monto:100,moneda:'PEN',
 fecha_comercial:'2026-09-01',vence_en:'2027-09-01',numero_transaccion:'F4-PERM-'+id,
 referencia:'ENSAYO FICTICIO',evidencia:{ruta:`${persona}/${id}/comprobante.png`}};
 return `select crm.preparar_inversion_fn(${q(id)},${q(JSON.stringify(datos))})`;};
const repetir=`select crm.confirmar_inversion_fn(${q(s.id)})`;
const nuevo=preparar();
function caso(nombre,fn){fn();pruebas.push({nombre,conforme:true});console.log('PASS: '+nombre);}
const deniega=(actor,consulta,setup='',codigo='42501')=>assert.throws(()=>como(actor,consulta,setup),new RegExp(codigo));
const gerencia=f.usuarios.gerencia.id,vendedor=f.usuarios.vendedor.id,ajeno=f.usuarios.ajeno.id;
const baja=`${sesion(gerencia)}do $baja$ begin
 perform crm.fijar_membresia_activa_fn(${q(vendedor)},false,${q(ajeno)},
 (select actualizado_en from crm.equipo where perfil_id=${q(vendedor)}),gen_random_uuid());end;$baja$;reset role;`;
try {
 sql("update crm.multiempresa_flags set activo=true where nombre='inversiones_escritura'");
 for(const actor of ['vendedor','supervisor','gerencia']) caso(`${actor} vigente: prepara y recupera su inversión`,()=>{
  assert(JSON.parse(como(f.usuarios[actor].id,nuevo)).solicitud_id);
  assert.equal(JSON.parse(como(f.usuarios[actor].id,repetir)).inversion_id,s.inversion_id);
 });
 for(const actor of ['ajeno','supervisor_ajeno','directorio','cliente']) caso(`${actor}: sin permiso de escritura sobre la relación`,()=>{
  deniega(f.usuarios[actor].id,nuevo);deniega(f.usuarios[actor].id,repetir);
 });
 caso('Una baja real revoca preparación y replay aunque conserve rol Portal analista',()=>{
  deniega(vendedor,nuevo,baja);deniega(vendedor,repetir,baja);
  assert.equal(como(vendedor,`select public.puede_ver_contrato(${q(s.resultado.fuente.id)})`,baja),'f');
 });
 caso('Reemplazo recibe la relación y el replay; nueva preparación exige datos propios',()=>{
  assert.equal(JSON.parse(como(ajeno,repetir,baja)).inversion_id,s.inversion_id);
  assert(JSON.parse(como(ajeno,nuevo,baja)).solicitud_id);
  assert.equal(como(ajeno,`select public.puede_ver_contrato(${q(s.resultado.fuente.id)})`,baja),'t');
 });
 caso('Baja sin reemplazo se rechaza y conserva personas e historia',()=>{
  assert.throws(()=>como(gerencia,`select crm.fijar_membresia_activa_fn(${q(vendedor)},false,null,
  (select actualizado_en from crm.equipo where perfil_id=${q(vendedor)}),gen_random_uuid())`),/requiere_reemplazo|reemplazo activo/);
 });
 // Persona histórica verificada sin responsable: Gerencia puede leer replay,
 // pero una operación nueva exige responsable activo. Solo se cambia la fixture.
 const sinResponsable=`update crm.inversionistas set responsable_relacion_id=null where id=${q(persona)};`;
 caso('Persona sin responsable: no se inventa uno para permitir la operación',()=>{
  deniega(gerencia,nuevo,sinResponsable,'P0409');
  deniega(vendedor,nuevo,sinResponsable);
  assert.equal(JSON.parse(como(gerencia,repetir,sinResponsable)).inversion_id,s.inversion_id);
 });
 caso('Directorio conserva agregados globales sin recibir filas, documentos ni escritura F4',()=>{
  const r=como(f.usuarios.directorio.id,`select public.puede_ver_contrato(${q(s.resultado.fuente.id)})`);
  assert.equal(r,'f');
  const reporte=JSON.parse(como(f.usuarios.directorio.id,"select crm.cierres_externos_fn('2026-09-01')"));
  assert.equal(reporte.alcance,'global');assert.deepEqual(reporte.cierres,[]);
  deniega(f.usuarios.directorio.id,nuevo);
 });
 caso('Cliente conserva su Portal y no recibe rol comercial por ser inversionista',()=>{
  assert.equal(como(f.usuarios.cliente.id,`select public.puede_ver_contrato(${q(s.resultado.fuente.id)})`),'t');
  deniega(f.usuarios.cliente.id,nuevo);
 });
 caso('Apagado F4 rechaza nueva escritura y reintento por igual',()=>{
  const apagada="update crm.multiempresa_flags set activo=false where nombre='inversiones_escritura';";
  deniega(vendedor,nuevo,apagada,'P0409');deniega(gerencia,repetir,apagada,'P0409');
 });
 assert.equal(sql(foto),original,'La matriz conserva fuentes, importes, atribución y sellos');
} finally {assert.equal(sqlOriginal(foto),original);}
writeFileSync(new URL(`../evidencia-f4/permisos-dinamicos-${copia.id}.json`,import.meta.url),JSON.stringify({
 entorno:'avancecorp-f4-bank',baseCopia:copia.nombre,terminadoEn:new Date().toISOString(),pruebas,
 bancoOriginalSinCambios:true,fuentesEconomicasYSellosSinCambios:true,
 sha256Oraculo:createHash('sha256').update(readFileSync(new URL(import.meta.url))).digest('hex'),
 limites:['SQL con rol/claims sintéticos; baja y traslado mediante RPC real. No simula una sesión HTTP.',
 'Los cambios de rol Portal/CRM y la matriz multirrol se cubren en su oráculo complementario.'],
},null,2)+'\n',{flag:'wx'});
console.log(`Permisos dinámicos: ${pruebas.length} grupos conformes.`);
