-- Reversión de ensayo LOCAL, sólo mientras existe la semilla OFF y ninguna
-- versión publicada. No usar para borrar un historial gerencial en producción.
begin;
do $$ begin
  if current_database() <> 'gestion_diaria_f4_vista_chvrqh' then
    raise exception 'Reversa sólo autorizada en la copia local F4';
  end if;
  perform private.assert_gestion_diaria();
  if exists(select 1 from crm.politica_gestion_diaria where version <> 1) then
    raise exception 'Hay versiones publicadas: no borrar historial';
  end if;
end $$;

do $$ declare v_def text; begin
  v_def := pg_get_functiondef('private.gestion_diaria_analista_core(uuid,date,timestamptz,timestamptz,timestamptz,timestamptz,uuid)'::regprocedure);
  execute replace(v_def, 'private.gestion_diaria_umbrales(p_ini)', 'private.gestion_diaria_umbrales()');
  v_def := pg_get_functiondef('private.gestion_diaria_equipo_core(date,uuid)'::regprocedure);
  v_def := replace(v_def, 'private.gestion_diaria_umbrales(v_ini)', 'private.gestion_diaria_umbrales()');
  execute replace(v_def, ', ''cortes'', private.gestion_diaria_cortes(v_dia, v_ids, v_ahora)', '');
  v_def := pg_get_functiondef('private.assert_gestion_diaria_analista()'::regprocedure);
  v_def := replace(v_def, '4dd5313e606b57485cd105b125f412b7', 'b08d96d051c210e24b1fb74484670b93');
  execute replace(v_def, '151860fa342b98d4f2ce9ed7054e390b', '6ab633af9f5356f3fa11cf309ff4b25c');
  v_def := pg_get_functiondef('private.assert_gestion_diaria_equipo()'::regprocedure);
  execute replace(v_def, '17b39a376af0f940f029937a6fa98186', '70d6b23ee4d9f1f397ccfbae8f1dee5a');
end $$;

create or replace function private.gestion_diaria_umbrales() returns jsonb
language sql stable security invoker set search_path to ''
as $function$
  select jsonb_build_object(
    'version', 1,
    'bien_min_pct', 45,
    'atencion_min_pct', 25,
    'minimo_llamadas_utiles', 5
  );
$function$;

create or replace function private.assert_gestion_diaria() returns text
language plpgsql stable security definer set search_path = ''
as $function$
begin
  return 'OK: Gestion Diaria [' || private.assert_gestion_diaria_registro()
    || '] [' || private.assert_gestion_diaria_resultado()
    || '] [' || private.assert_gestion_diaria_analista()
    || '] [' || private.assert_gestion_diaria_equipo() || ']';
end;
$function$;

drop function private.assert_gestion_diaria_cortes();
drop function private.gestion_diaria_cortes(date, uuid[], timestamptz);
drop function private.gestion_diaria_umbrales(timestamptz);
drop function private.politica_gestion_diaria_vigente(timestamptz);
drop table crm.politica_gestion_diaria;
drop function private.trg_politica_gestion_diaria_insertar();
comment on function crm.gestion_diaria_equipo_fn(date, uuid) is
  'Gestión Diaria F4: roster activo completo, actividad bajo RLS y pendientes actuales. Supervisor: su equipo; gerencia/lector global: equipo elegido o todos. Sin cortes ni escrituras.';
select private.assert_gestion_diaria();
select private.assert_sla_nucleo();
select private.assert_sla_operacion();
select private.assert_sla_comandos();
select private.assert_sla_avisos();
notify pgrst, 'reload schema';
commit;
