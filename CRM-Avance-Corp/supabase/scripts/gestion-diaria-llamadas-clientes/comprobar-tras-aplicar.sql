-- Comprobación de SOLO LECTURA tras aplicar 20261019170422 en producción (con `!`: `supabase db query --linked --file`).
-- Imprime una tabla con lo que debe salir: huellas selladas en los gates, gate de citas OK, y el rojo ajeno conocido
-- del analista/pulso («El cuerpo de crm.equipo_visible_fn() cambio … (md5 58bd05540d2a3eb576a7b648978707e7)») hasta que se
-- aplique 20261016211001. Los gates rojos lanzan P0001: se llaman a través de una función temporal que atrapa la excepción
-- para que la tabla se imprima entera. No escribe nada (pg_temp vive solo en esta sesión).
create function pg_temp.gate_sin_abortar(p_gate text) returns text language plpgsql as $$
declare v text;
begin
  execute format('select %s', p_gate) into v;
  return v;
exception when others then
  return 'ROJO (' || sqlstate || '): ' || sqlerrm;
end $$;
with huellas as (
  select 'ayudante' as objeto, md5(pg_get_functiondef('private.gestion_diaria_llamadas_clientes_eventos(timestamptz,timestamptz,uuid[])'::regprocedure)) as md5
  union all select 'lector', md5(pg_get_functiondef('private.gestion_diaria_llamadas_eventos(timestamptz,timestamptz,uuid[])'::regprocedure))
  union all select 'agregador', md5(pg_get_functiondef('private.gestion_diaria_llamadas(timestamptz,timestamptz,uuid[])'::regprocedure))
), gates as (
  select 'analista' as gate, pg_get_functiondef('private.assert_gestion_diaria_analista()'::regprocedure) as def
  union all select 'citas', pg_get_functiondef('private.assert_gestion_diaria_citas()'::regprocedure)
  union all select 'pulso', pg_get_functiondef('private.assert_gestion_diaria_pulso()'::regprocedure)
), veredictos as (
  select g.gate, (select string_agg(h.objeto, ',' order by h.objeto) from huellas h where g.def like '%' || h.md5 || '%') as sella,
         (g.def like '%_PENDIENTE_%') as con_placeholders,
         (g.def like '%-- 1b. El ayudante DEFINER de las llamadas a CLIENTES%') as con_seccion_1b
  from gates g
)
select * from veredictos
union all
select 'citas → ' || private.assert_gestion_diaria_citas(), null, null, null
union all
select 'analista → ' || pg_temp.gate_sin_abortar('private.assert_gestion_diaria_analista()'), null, null, null
union all
select 'pulso → ' || pg_temp.gate_sin_abortar('private.assert_gestion_diaria_pulso()'), null, null, null
order by 1;
