-- SOLO LECTURA. Sellos de conversión y de capital, y plazos de carga de septiembre y octubre de 2026.
begin read only;
select 'conversion' as sello, pc.periodo::text, to_char(pc.cerrado_en at time zone 'America/Lima', 'DD/MM HH24:MI') as cuando from crm.periodos_cerrados pc where pc.periodo >= date '2026-08-01'
union all
select 'capital', s.periodo::text, '' from crm.capital_mes_sellos s where s.periodo >= date '2026-08-01'
union all
select 'plazo_hasta', m::text, to_char(private.conversion_plazo_hasta(m) at time zone 'America/Lima', 'DD/MM/YYYY HH24:MI') from unnest(array[date '2026-09-01', date '2026-10-01']) m
union all
select 'ahora', '', to_char(clock_timestamp() at time zone 'America/Lima', 'DD/MM/YYYY HH24:MI')
order by 1, 2;
rollback;
