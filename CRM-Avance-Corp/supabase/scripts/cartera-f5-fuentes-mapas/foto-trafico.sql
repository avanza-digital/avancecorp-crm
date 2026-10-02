-- SOLO LECTURA: foto del tráfico real (pg_stat_statements acumulado desde el arranque) de las puertas que usan la cartera F5.
-- Tomar una ANTES de aplicar y otra al día siguiente; la media del tramo = (total_ms_después - total_ms_antes) / (llamadas_después - llamadas_antes).
select now() as t, (select md5(pg_get_functiondef('private.cartera_f5_fuentes()'::regprocedure))) as huella_fuentes,
  substring(query from '"crm"\."([a-z0-9_]+)"') as funcion, calls, round(total_exec_time::numeric) as total_ms, round(mean_exec_time::numeric,1) as media_ms
from pg_stat_statements
where query ilike '%pgrst%' and substring(query from '"crm"\."([a-z0-9_]+)"') in
  ('inversionista_ficha_fn','postventa_agenda_fn','cartera_inversionistas_filtrada_fn','cartera_inversionistas_estado_fn','postventa_estado_fn','inversionista_gestion_fn','postventa_ficha_fn','inversionista_cuentas_fn')
order by 3, calls desc;
