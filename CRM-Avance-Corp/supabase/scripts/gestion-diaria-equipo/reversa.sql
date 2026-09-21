-- Sólo retira la etapa 1 de F4; no toca datos, F1–F3 ni SLA.
begin;
create or replace function private.assert_gestion_diaria() returns text
language plpgsql stable security definer set search_path = ''
as $function$
declare
  v_registro text;
  v_resultado text;
  v_analista text;
begin
  v_registro := private.assert_gestion_diaria_registro();
  v_resultado := private.assert_gestion_diaria_resultado();
  v_analista := private.assert_gestion_diaria_analista();
  return 'OK: Gestion Diaria [' || v_registro || '] [' || v_resultado || '] [' || v_analista || ']';
end;
$function$;
drop function if exists crm.gestion_diaria_equipo_fn(date, uuid);
drop function if exists private.gestion_diaria_equipo_core(date, uuid);
drop function if exists private.gestion_diaria_equipo_pendientes();
drop function if exists private.assert_gestion_diaria_equipo();
select private.assert_gestion_diaria();
notify pgrst, 'reload schema';
commit;
