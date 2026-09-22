-- F4: separar la lectura SLA de los locks de presentación/reconocimiento.
-- El POST confirma cortes; la UI refresca el contexto mediante un GET posterior.
begin;
do $preflight$ begin
  perform private.assert_gestion_diaria();
  perform private.assert_sla_nucleo(); perform private.assert_sla_operacion();
  perform private.assert_sla_comandos(); perform private.assert_sla_avisos();
end $preflight$;

do $separar$
declare fuente text; nueva text;
begin
  if (select md5(prosrc) from pg_proc where oid='private.gestion_diaria_avisos(timestamptz)'::regprocedure)
    <> '9479e6066fc5724eb7b535514a4acba8' then raise exception 'F4: lector compuesto inesperado'; end if;
  fuente := pg_get_functiondef('private.gestion_diaria_avisos(timestamptz)'::regprocedure);
  nueva := replace(fuente, ' || private.gestion_diaria_contexto(v_ids,p_ahora,v_alertas)', '');
  if nueva=fuente then raise exception 'F4: falta composición esperada'; end if;
  execute nueva;
  if (select md5(prosrc) from pg_proc where oid='private.gestion_diaria_avisos(timestamptz)'::regprocedure)
    <> '7009218260658cfbf6ed096715d2a8d5' then raise exception 'F4: núcleo de cortes inesperado'; end if;
end $separar$;

create function private.gestion_diaria_avisos_con_contexto(p_ahora timestamptz) returns jsonb
language plpgsql volatile security definer set search_path = '' as $function$
declare v_avisos jsonb; v_ids uuid[];
begin
  v_avisos := private.gestion_diaria_avisos(p_ahora);
  select coalesce(array_agg(e.perfil_id), '{}'::uuid[]) into v_ids
    from crm.equipo_visible_fn() e where e.activo and e.rol_crm='vendedor'
      and e.perfil_id in (select private.vendedor_ids_visibles(auth.uid()));
  return v_avisos || private.gestion_diaria_contexto(v_ids,p_ahora,v_avisos->'alertas');
end $function$;
revoke all on function private.gestion_diaria_avisos_con_contexto(timestamptz) from public,anon,authenticated,service_role;
grant create on schema private to crm_gestion_diaria_lector;
alter function private.gestion_diaria_avisos_con_contexto(timestamptz) owner to crm_gestion_diaria_lector;
revoke create on schema private from crm_gestion_diaria_lector;
grant execute on function private.gestion_diaria_avisos_con_contexto(timestamptz) to postgres;

create or replace function crm.gestion_diaria_avisos_fn() returns jsonb
language sql volatile security definer set search_path = '' as $function$
  select private.gestion_diaria_avisos_con_contexto(clock_timestamp());
$function$;
revoke all on function crm.gestion_diaria_avisos_fn() from public,anon,authenticated,service_role;
grant execute on function crm.gestion_diaria_avisos_fn() to authenticated;

do $sellos$ declare fuente text; begin
  fuente := pg_get_functiondef('private.assert_gestion_diaria_avisos()'::regprocedure);
  if strpos(fuente,'9479e6066fc5724eb7b535514a4acba8')=0
    or strpos(fuente,'e43dc496abf8f1d6fefd081c82af3dab')=0 then
    raise exception 'F4: sellos previos inesperados';
  end if;
  execute replace(replace(fuente,'9479e6066fc5724eb7b535514a4acba8','7009218260658cfbf6ed096715d2a8d5'),
    'e43dc496abf8f1d6fefd081c82af3dab','b127baa4eea8b60ede38ea8b53ec51ca');
end $sellos$;

create function private.assert_gestion_diaria_lectura() returns text
language plpgsql stable security definer set search_path = '' as $function$
begin
  if not exists(select 1 from pg_proc p where p.oid=to_regprocedure('private.gestion_diaria_avisos_con_contexto(timestamptz)')
    and md5(p.prosrc)='9e668921b73ae1b3d023bb66bcd924b0'
    and p.proowner='crm_gestion_diaria_lector'::regrole and p.prosecdef and p.provolatile='v'
    and p.proconfig=array['search_path=""'] and has_function_privilege('postgres',p.oid,'EXECUTE')
    and not has_function_privilege('authenticated',p.oid,'EXECUTE')
    and not has_function_privilege('anon',p.oid,'EXECUTE')
    and not has_function_privilege('service_role',p.oid,'EXECUTE')) then
    raise exception 'F4: lectura completa o permisos alterados';
  end if;
  if not has_schema_privilege('crm_gestion_diaria_lector','auth','USAGE')
    or not has_function_privilege('crm_gestion_diaria_lector','auth.uid()','EXECUTE') then
    raise exception 'F4: lector sin acceso heredado a identidad';
  end if;
  return 'OK: lectura completa bajo RLS; escrituras de cortes sin cómputo SLA';
end $function$;
revoke all on function private.assert_gestion_diaria_lectura() from public,anon,authenticated,service_role;

do $gate$ declare fuente text; nueva text; begin
  fuente := pg_get_functiondef('private.assert_gestion_diaria()'::regprocedure);
  nueva := replace(fuente, $a$|| private.assert_gestion_diaria_alertas_equipo() || ']';$a$, $a$|| private.assert_gestion_diaria_alertas_equipo() || '] [' || private.assert_gestion_diaria_lectura() || ']';$a$);
  if nueva=fuente then raise exception 'F4: gate de contexto no encontrado'; end if;
  execute nueva;
end $gate$;
do $postflight$ begin
  perform private.assert_gestion_diaria();
  perform private.assert_sla_nucleo(); perform private.assert_sla_operacion();
  perform private.assert_sla_comandos(); perform private.assert_sla_avisos();
end $postflight$;
notify pgrst,'reload schema';
commit;
