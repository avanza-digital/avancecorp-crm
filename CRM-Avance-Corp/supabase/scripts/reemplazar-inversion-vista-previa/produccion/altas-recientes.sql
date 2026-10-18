-- SOLO LECTURA. Altas de contrato de las últimas 3 horas (a qué cliente fueron) y si 999901/999902 ya existen.
begin read only;
select c.numero_contrato, p.nombre_completo as cliente, left(c.cliente_id::text, 8) as cliente_id, c.capital::text, c.moneda,
       c.es_demo, to_char(c.creado_en at time zone 'America/Lima', 'HH24:MI') as hora_lima
from public.contratos c join public.perfiles p on p.id = c.cliente_id
where c.creado_en > now() - interval '3 hours' or c.numero_contrato in ('2026-01-999901', '2026-01-999902')
order by c.creado_en desc
limit 10;
rollback;
