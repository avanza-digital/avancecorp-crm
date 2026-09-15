import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {sql,ajustes} from './banco-local.mjs';

const leer=(ruta)=>readFileSync(new URL(ruta,import.meta.url),'utf8');
const cuerpo=(texto)=>texto.replace(/^begin;\s*/m,'').replace(/^commit;\s*$/m,'');
const migracion=cuerpo(leer('../../migrations/20260915170237_crm_ficha_lectura_individual.sql'));
const reversa=cuerpo(leer('./REVERSA.sql'));
const casos=leer('./casos-limite.sql');
const huellas=`select jsonb_agg(x order by x.firma) from (
 select p.oid::regprocedure::text firma,md5(pg_get_functiondef(p.oid)) md5,p.proacl::text acl,p.proowner propietario,p.proconfig configuracion
 from pg_proc p where p.oid in ('private.cartera_f5_personas_visibles()'::regprocedure,
 'crm.inversionista_ficha_fn(uuid,integer,integer)'::regprocedure)) x;`;
const inicial=JSON.parse(sql(huellas));
assert.equal(sql("select to_regprocedure('private.cartera_f5_personas_visibles(uuid)') is null;"),'t');
const original=sql("select pg_get_functiondef('private.cartera_f5_personas_visibles()'::regprocedure);")+';';
const deriva=original.replace('AS $function$','AS $function$\n -- deriva artificial solo para comprobar el rechazo');
const resultados=[];
function rechazo(nombre,consulta,mensaje) {
 assert.throws(()=>sql(`begin;${ajustes}${consulta}rollback;`),mensaje);
 assert.deepEqual(JSON.parse(sql(huellas)),inicial,'Una prueba fallida dejó cambios');
 resultados.push({prueba:nombre,resultado:'PASS'});
}
rechazo('aplicacion_repetida',migracion+migracion,/La variante individual ya existe/);
rechazo('deriva_previa',deriva+migracion,/Cambió el núcleo o la ficha/);
rechazo('reversa_con_deriva',migracion+deriva+reversa,/Deriva posterior al cambio/);
rechazo('acl_no_ensayada',"grant execute on function private.cartera_f5_personas_visibles() to authenticated;"+migracion,/ACL final no ensayada/);
rechazo('codigo_final_alterado',migracion.replace('and (p_inversionista is null or i.id=(select id from destino))','and true'),/Definición o configuración final no ensayada/);
assert.deepEqual(JSON.parse(sql(`begin;${ajustes}${migracion}${reversa}${huellas}rollback;`)),inicial);
resultados.push({prueba:'reversa_exacta_incluye_acl',resultado:'PASS'});
for(const rol of ['anon','authenticated','service_role']) {
 rechazo(`nucleo_privado_${rol}`,`${migracion}set local role ${rol};select * from private.cartera_f5_personas_visibles(null::uuid);`,/permission denied/);
}
// Revocaciones durante la llamada: se instrumenta SOLO el contexto F4 en la copia
// local y se revierte. Permite comprobar que la segunda validación se ejecuta.
// No se presenta como prueba de dos sesiones concurrentes.
for(const fase of ['antes','despues']) {
 for(const escenario of ['bandera','reasignacion','fusion']) {
  const cambio=escenario==='bandera'
   ? "update crm.multiempresa_flags set activo=false where nombre='ficha_360_neutral';"
   : escenario==='reasignacion'
    ? `update crm.inversionistas set responsable_relacion_id=(select perfil_id from crm.equipo
       where rol_crm='vendedor' and activo and perfil_id<>auth.uid() order by perfil_id limit 1) where id=p_persona;`
    : `update crm.inversionistas set estado='fusionado',fusionado_en=now(),
       inversionista_canonico_id=md5('ficha-limite-persona-6')::uuid where id=p_persona;`;
  const salida=sql(`begin;${ajustes}
   update crm.multiempresa_flags set activo=true where nombre in
    ('resolver_en_puertas','ficha_360_neutral','inversiones_escritura','postventa_neutral');
   ${casos}${fase==='despues'?migracion:''}
   create or replace function private.inversion_persona_contexto(p_persona uuid) returns jsonb
   language plpgsql security definer set search_path='' as $instrumentacion$
   begin
    set local session_replication_role='replica';${cambio}set local session_replication_role='origin';
    return '{}'::jsonb;
   end; $instrumentacion$;
   do $comprobar$
   declare dato jsonb; codigo text;
   begin
    perform set_config('request.jwt.claim.sub',(select analista::text from prueba_responsables),true);
    begin
     set local role authenticated;
     dato:=crm.inversionista_ficha_fn(md5('ficha-limite-persona-2')::uuid);
    exception when others then codigo:=sqlstate;
    end;
    reset role;
    if '${escenario}'='bandera' then
     if codigo is distinct from 'P0409' then raise exception 'No se revalidó la bandera: %',codigo; end if;
    elsif codigo is not null or dato is not null then
     raise exception 'La ficha sobrevivió a la revocación %: %','${escenario}',codigo;
    end if;
   end; $comprobar$;
   select jsonb_build_object('resultado','PASS','fase','${fase}','prueba','revocacion_${escenario}');
   rollback;`);
  resultados.push(JSON.parse(salida));
 }
}
assert.deepEqual(JSON.parse(sql(huellas)),inicial,'La instrumentación no se revirtió');
const evidencias=new URL('./evidencias/',import.meta.url);mkdirSync(evidencias,{recursive:true});
const fichaResultante=sql(`begin;${ajustes}${migracion}
 select pg_get_functiondef('crm.inversionista_ficha_fn(uuid,integer,integer)'::regprocedure);rollback;`);
writeFileSync(new URL('ficha-resultante.sql',evidencias),'-- Evidencia del resultado ensayado; instalar únicamente mediante la migración, no este archivo.\n'+fichaResultante+';\n');
writeFileSync(new URL('seguridad-local.json',evidencias),JSON.stringify(resultados,null,2)+'\n');
console.log(JSON.stringify(resultados));
