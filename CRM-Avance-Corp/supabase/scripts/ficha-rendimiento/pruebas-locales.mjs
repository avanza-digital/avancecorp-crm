// Prueba aislada de equivalencia. Destino fijo; no lee URLs ni claves de entorno.
// La copia inicial se crea desde multiempresa_f8_ajustes_20260914 sin alterarla.
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {sql,base} from './banco-local.mjs';
const migracion=readFileSync(new URL('../../migrations/20260915170237_crm_ficha_lectura_individual.sql',import.meta.url),'utf8')
 .replace(/^begin;\s*/m,'').replace(/^commit;\s*$/m,'');
const evidencias=new URL('./evidencias/',import.meta.url);
mkdirSync(evidencias,{recursive:true});
const casos=readFileSync(new URL('./casos-limite.sql',import.meta.url),'utf8');
const controles=`
create temporary table prueba_actores as
 select p.id uid,coalesce(e.rol_crm,p.rol) rol,p.activo and coalesce(e.activo,true) activo
 from public.perfiles p left join crm.equipo e on e.perfil_id=p.id
 where e.perfil_id is not null or p.rol='directorio'
 union all select null::uuid,'sin_sesion',false;
insert into prueba_actores select p.id,'cliente',p.activo from public.perfiles p where p.rol='cliente' limit 1;
create temporary table prueba_personas as select id from crm.inversionistas
 union select '00000000-0000-0000-0000-000000000001'::uuid
 union select null::uuid;
create temporary table prueba_nucleo(fase text,uid uuid,persona uuid,dato jsonb);
create temporary table prueba_fichas(fase text,uid uuid,rol text,persona uuid,pagina integer,dato jsonb);
create temporary table prueba_permisos as
 select oid,proowner,proacl,proconfig,prosecdef,provolatile,pg_get_function_arguments(oid) argumentos
 from pg_proc where oid in ('private.cartera_f5_personas_visibles()'::regprocedure,
 'crm.inversionista_ficha_fn(uuid,integer,integer)'::regprocedure);
`;
function captura(fase) {
 return `do $captura$
 declare a record; p record; pagina integer; completo jsonb; dato jsonb; canonica uuid;
 begin
 for a in select * from prueba_actores loop
  perform set_config('request.jwt.claim.sub',coalesce(a.uid::text,''),true);
  select coalesce(jsonb_agg(to_jsonb(x) order by x.inversionista_id),'[]') into completo
   from private.cartera_f5_personas_visibles() x;
  insert into prueba_nucleo values('${fase}',a.uid,null,completo);
  for p in select * from prueba_personas loop
   ${fase==='antes' ? `
   canonica:=private.inversionista_canonica(p.id);
   select coalesce(jsonb_agg(x order by x->>'inversionista_id'),'[]') into dato
    from jsonb_array_elements(completo) x where p.id is null or (x->>'inversionista_id')::uuid=canonica;
   ` : `
   select coalesce(jsonb_agg(to_jsonb(x) order by x.inversionista_id),'[]') into dato
    from private.cartera_f5_personas_visibles(p.id) x;
   `}
   insert into prueba_nucleo values('${fase}',a.uid,p.id,dato);
   for pagina in 1..2 loop
    begin
     set local role authenticated;
     dato:=jsonb_build_object('ok',true,'ficha',crm.inversionista_ficha_fn(p.id,pagina,pagina));
    exception when others then dato:=jsonb_build_object('sqlstate',sqlstate);
    end;
    reset role;
    insert into prueba_fichas values('${fase}',a.uid,a.rol,p.id,pagina,dato);
   end loop;
  end loop;
 end loop;
 end;
 $captura$;`;
}
function inactivos(fase) {
 return `do $inactivos$
 declare uid uuid; causa text; dato jsonb;
 begin
 select analista into uid from prueba_responsables;
 perform set_config('request.jwt.claim.sub',uid::text,true);
 foreach causa in array array['perfil','equipo'] loop
  set local session_replication_role='replica';
  if causa='perfil' then update public.perfiles set activo=false where id=uid;
  else update crm.equipo set activo=false where perfil_id=uid; end if;
  set local session_replication_role='origin';
  begin
   set local role authenticated;
   dato:=jsonb_build_object('ficha',crm.inversionista_ficha_fn(md5('ficha-limite-persona-2')::uuid));
  exception when others then dato:=jsonb_build_object('sqlstate',sqlstate);
  end;
  reset role;
  insert into prueba_inactivos values('${fase}',causa,dato);
  set local session_replication_role='replica';
  if causa='perfil' then update public.perfiles set activo=true where id=uid;
  else update crm.equipo set activo=true where perfil_id=uid; end if;
  set local session_replication_role='origin';
 end loop;
 end; $inactivos$;`;
}
const consulta=`
begin;
set local statement_timeout='90s';
set local jit=off;
set local work_mem='3500kB';
set local random_page_cost=1.1;
do $destino$ begin if current_database()<>'${base}' then raise exception 'Destino no autorizado'; end if; end; $destino$;
update crm.multiempresa_flags set activo=true
 where nombre in ('resolver_en_puertas','ficha_360_neutral','inversiones_escritura','postventa_neutral');
${casos}
${controles}
do $h$ begin perform pg_temp.capturar_huellas('antes'); end; $h$;
${captura('antes')}
${inactivos('antes')}
${migracion}
${captura('despues')}
${inactivos('despues')}
do $h$ begin perform pg_temp.capturar_huellas('despues'); end; $h$;
do $paridad$
begin
 if exists(select 1 from prueba_fichas where persona is null and dato#>'{ficha,persona}' is not null) then
  raise exception 'Una entrada NULL expuso una ficha'; end if;
 if exists(select 1 from prueba_huellas group by tabla having count(distinct huella)<>1) then
  raise exception 'Cambió una fuente económica o su identidad'; end if;
 if (select count(*) from prueba_inactivos where dato->>'sqlstate'='42501')<>4 then
  raise exception 'Un actor inactivo obtuvo acceso o cambió el rechazo'; end if;
 if exists(select 1 from prueba_fichas where fase='despues' and
  persona in (md5('ficha-limite-persona-1')::uuid,md5('ficha-limite-persona-3')::uuid,md5('ficha-limite-canonica-3')::uuid)
  and dato#>'{ficha,persona}' is not null) then raise exception 'Se filtró una identidad con solo demos'; end if;
 if (select count(*) from prueba_fichas where fase='despues' and rol='gerencia' and pagina=1
  and persona in (md5('ficha-limite-persona-2')::uuid,md5('ficha-limite-persona-4')::uuid,md5('ficha-limite-canonica-4')::uuid)
  and (dato#>>'{ficha,inversiones_total}')::int=1)<>3 then raise exception 'El caso mixto no excluyó el contrato demo'; end if;
 if not exists(select 1 from prueba_fichas where fase='despues' and rol='supervisor'
  and uid=(select supervisor from prueba_responsables) and persona=md5('ficha-limite-persona-5')::uuid
  and dato#>'{ficha,persona}' is not null) then raise exception 'No se cubrió la bandeja del supervisor'; end if;
 if exists(select 1 from prueba_fichas where fase='despues' and rol='vendedor'
  and persona=md5('ficha-limite-persona-5')::uuid and dato#>'{ficha,persona}' is not null) then
  raise exception 'La bandeja sin analista se filtró a vendedores'; end if;
 if not exists(select 1 from prueba_fichas where fase='despues' and rol='gerencia'
  and persona=md5('ficha-limite-persona-6')::uuid and (dato#>>'{ficha,inversiones_total}')::int=0) then
  raise exception 'Se perdió la identidad provisional'; end if;
 if exists (
  (select uid,persona,dato from prueba_nucleo where fase='antes' except all select uid,persona,dato from prueba_nucleo where fase='despues')
  union all
  (select uid,persona,dato from prueba_nucleo where fase='despues' except all select uid,persona,dato from prueba_nucleo where fase='antes')
 ) then raise exception 'Cambió un campo del núcleo o una identidad fusionada'; end if;
 if exists (
  (select uid,rol,persona,pagina,dato from prueba_fichas where fase='antes' except all select uid,rol,persona,pagina,dato from prueba_fichas where fase='despues')
  union all
  (select uid,rol,persona,pagina,dato from prueba_fichas where fase='despues' except all select uid,rol,persona,pagina,dato from prueba_fichas where fase='antes')
 ) then raise exception 'Cambió una ficha completa, su permiso o su paginación'; end if;
 if exists(select 1 from prueba_permisos b join pg_proc a on a.oid=b.oid
  where (a.proowner,a.proacl,a.proconfig,a.prosecdef,a.provolatile,pg_get_function_arguments(a.oid))
    is distinct from (b.proowner,b.proacl,b.proconfig,b.prosecdef,b.provolatile,b.argumentos)) then
  raise exception 'Cambió firma, permiso, propietario o configuración existente'; end if;
 if exists(select 1 from (values('anon'),('authenticated'),('service_role')) r(rol)
  where has_function_privilege(r.rol,'private.cartera_f5_personas_visibles(uuid)','execute')) then
  raise exception 'El núcleo individual quedó expuesto'; end if;
 if exists(select 1 from (values('gerencia'),('supervisor'),('vendedor'),('directorio')) r(rol)
  where not exists(select 1 from prueba_fichas f where f.fase='despues' and f.rol=r.rol and f.dato#>'{ficha,persona}' is not null)) then
  raise exception 'Falta cobertura positiva de un rol'; end if;
 if not exists(select 1 from prueba_fichas where fase='despues' and dato->>'sqlstate'='42501') then
  raise exception 'Falta cobertura denegada'; end if;
end; $paridad$;
select jsonb_build_object('resultado','PASS','base',current_database(),
 'contextos',(select count(*) from prueba_actores),
 'personas_entrada',(select count(*) from prueba_personas),
 'aliases',(select count(*) from crm.inversionistas where inversionista_canonico_id is not null),
 'nucleo_comparaciones',(select count(*) from prueba_nucleo where fase='antes'),
 'fichas_comparaciones',(select count(*) from prueba_fichas where fase='antes'),
 'por_rol',(select jsonb_agg(x) from (select rol,count(*) total,
  count(*) filter(where dato#>'{ficha,persona}' is not null) visibles,
  count(*) filter(where dato->>'sqlstate'='42501') denegadas
  from prueba_fichas where fase='despues' group by rol order by rol) x),
 'contrato_publico_y_acl','PASS','nucleo_privado','PASS');
select jsonb_build_object('casos_limite','PASS','huellas_conservadas',(select count(distinct tabla) from prueba_huellas),
 'inactivos_denegados',(select count(*) from prueba_inactivos),
 'funciones',(select jsonb_agg(x) from (select p.oid::regprocedure::text firma,md5(pg_get_functiondef(p.oid)) md5
  from pg_proc p where p.oid in ('private.cartera_f5_personas_visibles()'::regprocedure,
  'private.cartera_f5_personas_visibles(uuid)'::regprocedure,'crm.inversionista_ficha_fn(uuid,integer,integer)'::regprocedure)) x));
rollback;
`;
const r=sql(consulta).split('\n').map(JSON.parse);
writeFileSync(new URL('paridad-local.json',evidencias),JSON.stringify(r,null,2)+'\n');
console.log(JSON.stringify(r));
