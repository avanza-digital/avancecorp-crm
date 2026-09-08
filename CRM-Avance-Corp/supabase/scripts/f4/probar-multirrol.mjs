import assert from 'node:assert/strict';
import {randomUUID,createHash} from 'node:crypto';
import {readFileSync,writeFileSync} from 'node:fs';
import {paresAutoridadSql} from './configuracion-publicada.mjs';
import {crearCopiaSql} from './copia-sql-local.mjs';
import {leer,literal as q,sql as originalSql} from './banco-local.mjs';
const f=leer('fixtures.json'),base=leer('operaciones-base.json'),g=f.usuarios.gerencia.id,v=f.usuarios.vendedor.id,otro=f.usuarios.ajeno.id;
const copia=crearCopiaSql('multirrol'),{sql}=copia,pruebas=[];
const j=x=>q(JSON.stringify(x)),claims=a=>`set local request.jwt.claims=${j({sub:a,role:'authenticated'})};set local role authenticated;`;
const ejecutar=(texto)=>sql(`\\set VERBOSITY verbose
begin;set local statement_timeout='15s';${texto};rollback;`);
const foto=`select private.idem_hash(jsonb_build_object('perfiles',(select jsonb_agg(to_jsonb(p) order by id) from public.perfiles p),
 'equipo',(select jsonb_agg(to_jsonb(e) order by perfil_id) from crm.equipo e),
 'contratos',(select jsonb_agg(to_jsonb(c) order by id) from public.contratos c),
 'inversiones',(select jsonb_agg(to_jsonb(i) order by id) from crm.inversiones i)))`;
const antes=originalSql(foto);assert.equal(sql(foto),antes);
const superadmin=randomUUID();
const semilla=`insert into auth.users(id) values(${q(superadmin)});insert into public.perfiles(id,nombre_completo,rol,activo)
 values(${q(superadmin)},'SUPERADMIN FICTICIO DEL ENSAYO','superadmin',true);`;
const id=randomUUID(),d={inversionista_id:base.identidades.avance,empresa:'qorilazo',monto:100,moneda:'PEN',fecha_comercial:'2026-09-01',vence_en:'2027-09-01',
 numero_transaccion:'F4-MULTI-'+id,referencia:'FICTICIO',evidencia:{ruta:`${base.identidades.avance}/${id}/p.png`}};
const prep=`select crm.preparar_inversion_fn(${q(id)},${j(d)})`;
const s=JSON.parse(sql(`select to_jsonb(s) from crm.inversion_solicitudes s where inversionista_id=${q(base.identidades.avance)} and estado='confirmada' limit 1`));
const replay=`select crm.confirmar_inversion_fn(${q(s.id)})`;
const baja=`${claims(g)}do $b$ begin perform crm.fijar_membresia_activa_fn(${q(v)},false,${q(otro)},
 (select actualizado_en from crm.equipo where perfil_id=${q(v)}),gen_random_uuid());end;$b$;reset role;`;
function caso(nombre,fn){fn();pruebas.push({nombre,conforme:true});console.log('PASS: '+nombre);}
try{
 sql(paresAutoridadSql);
 sql("update crm.multiempresa_flags set activo=true where nombre='inversiones_escritura'");
 const cambiaPortal=`${semilla}${claims(superadmin)}update public.perfiles set rol='comercial' where id=${q(v)};reset role;`;
 caso('Cambio real de rol Portal a comercial conserva membresía CRM explícita',()=>{
  assert.equal(ejecutar(cambiaPortal+`select rol||':'||(select rol_crm from crm.equipo where perfil_id=${q(v)}) from public.perfiles where id=${q(v)}`),'comercial:vendedor');
  assert(JSON.parse(ejecutar(cambiaPortal+claims(v)+prep)).solicitud_id);
 });
 caso('Par Portal comercial/CRM vendedor no extiende el ámbito a otro equipo',()=>{
  const fuera={...d,inversionista_id:base.identidades.prodelco};
  // Reasignación real de esa relación al segundo equipo, antes de invocar actor multirrol.
  const mueve=`${claims(g)}select crm.reasignar_responsable_relacion_fn(${q(base.identidades.prodelco)},${q(otro)},'Reasignación ficticia para probar ámbito de usuario multirrol');reset role;`;
  assert.throws(()=>ejecutar(cambiaPortal+mueve+claims(v)+`select crm.preparar_inversion_fn(${q(id)},${j(fuera)})`),/42501/);
 });
 caso('Baja revoca también al actor multirrol; el rol Portal no mantiene escritura ni replay',()=>{
  for(const op of [prep,replay]) assert.throws(()=>ejecutar(cambiaPortal+baja+claims(v)+op),/42501/);
 });
 caso('Suspensión Portal retira permiso CRM efectivo sin reescribir membresía',()=>{
  const suspende=`${semilla}${claims(superadmin)}update public.perfiles set activo=false where id=${q(v)};reset role;`;
  for(const op of [prep,replay]) assert.throws(()=>ejecutar(suspende+claims(v)+op),/42501/);
 });
 caso('Gerencia CRM activa funciona con su rol Portal admin separado',()=>{
  assert(JSON.parse(ejecutar(claims(g)+prep)).solicitud_id);
 });
 caso('Superadmin Portal sin membresía comercial no recibe escritura F4',()=>{
  for(const op of [prep,replay]) assert.throws(()=>ejecutar(semilla+claims(superadmin)+op),/42501/);
 });
 const version=`do $v$ begin perform set_config('f4.prueba_version',
  (select actualizado_en::text from crm.equipo where perfil_id=${q(v)}),true);end;$v$;`;
 const argVersion="current_setting('f4.prueba_version')::timestamptz";
 caso('Cambio real a coordinador se impide con jerarquía comercial todavía activa',()=>{
  assert.throws(()=>ejecutar(cambiaPortal+version+claims(superadmin)+`select crm.asignar_rol_usuario_fn(${q(v)},'coordinador',
  ${argVersion},gen_random_uuid())`),/depend|clientes|leads|responsable|supervisor/);
 });
 caso('Tras baja, traslado y ajuste de jerarquía, el coordinador no recupera escritura',()=>{
  const sinSupervisor=version+claims(g)+`do $j$ begin perform crm.actualizar_jerarquia_usuario_fn(${q(v)},null,
   ${argVersion},gen_random_uuid());end;$j$;reset role;`;
  const cambio=cambiaPortal+baja+sinSupervisor+version+claims(superadmin)+`do $c$ begin perform crm.asignar_rol_usuario_fn(${q(v)},'coordinador',
   ${argVersion},gen_random_uuid());end;$c$;reset role;`;
  assert.equal(ejecutar(cambio+`select rol_crm||':'||activo::text from crm.equipo where perfil_id=${q(v)}`),'coordinador:false');
  assert.throws(()=>ejecutar(cambio+claims(v)+prep),/42501/);
 });
 caso('Invariantes impiden combinar Directorio Portal con vendedor CRM activo',()=>{
  assert.throws(()=>ejecutar(semilla+claims(superadmin)+`update public.perfiles set rol='directorio' where id=${q(v)}`),/Directorio|directorio/);
 });
 caso('Cliente y vendedor en la misma cuenta sigue siendo un par no declarado',()=>{
  assert.throws(()=>ejecutar(semilla+claims(superadmin)+`update public.perfiles set rol='cliente' where id=${q(v)}`),/42501/);
 });
 caso('Cliente sin membresía no puede autoasignarse rol comercial',()=>{
  assert.throws(()=>ejecutar(claims(f.usuarios.cliente.id)+`select crm.asignar_rol_usuario_fn(${q(f.usuarios.cliente.id)},'vendedor',null,gen_random_uuid())`),/42501/);
 });
 caso('Los ensayos con rollback conservan perfiles, equipo, atribución y fuentes',()=>assert.equal(sql(foto),antes));
}finally{assert.equal(originalSql(foto),antes);}
writeFileSync(new URL(`../evidencia-f4/multirrol-${copia.id}.json`,import.meta.url),JSON.stringify({entorno:'avancecorp-f4-bank',baseCopia:copia.nombre,
 terminadoEn:new Date().toISOString(),pruebas,bancoOriginalSinCambios:true,sha256Oraculo:createHash('sha256').update(readFileSync(new URL(import.meta.url))).digest('hex'),
 limite:'Fixture Superadmin sintética sin login ni contraseña; cambios de perfil por UPDATE autorizado, rol y baja mediante RPC reales bajo claims SQL. Todos los casos revierten su transacción.',
},null,2)+'\n',{flag:'wx'});
console.log(`Multirrol: ${pruebas.length} grupos conformes.`);
