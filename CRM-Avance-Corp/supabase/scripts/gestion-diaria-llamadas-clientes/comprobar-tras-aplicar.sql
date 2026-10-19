-- Comprobación de SOLO LECTURA tras aplicar 20261019170422 en producción (con `!`: `supabase db query --linked --file`).
-- Imprime una tabla con lo que debe salir: huellas selladas en los gates, gate de citas OK, y el rojo ajeno conocido
-- del analista/pulso (crm.equipo_visible_fn 58bd0554…) hasta que se aplique 20261016211001. No escribe nada.
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
select 'analista → ' || coalesce((select private.assert_gestion_diaria_analista()), '?'), null, null, null
order by 1;
