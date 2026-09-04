-- Las piezas que hoy estan en observacion, tal como las declara el LIBRO.
-- Se lee del servidor a proposito: una lista quemada en el guion envejece y
-- acabaria acreditando una pieza que ya no esta condenada (o callando una nueva).
--
-- Un solo SELECT: `supabase db query` solo devuelve el ULTIMO resultado del
-- archivo (trampa medida en el gate de la Ola 0).
begin read only;

select json_agg(p order by p.ola, p.firma) as piezas
from (
  select
    firma,
    ola,
    estado,
    cerrada_en,
    drop_no_antes_de,
    -- El nombre por el que PostgREST la expone: /rest/v1/rpc/<nombre>
    split_part(split_part(firma, '(', 1), '.', 2) as nombre_rpc,
    split_part(firma, '.', 1)                     as esquema,
    (cerrada_en + 7)  as d7,
    (cerrada_en + 14) as d14
  from private.f7_piezas_en_observacion
  where estado = 'observacion'
) p;

rollback;
