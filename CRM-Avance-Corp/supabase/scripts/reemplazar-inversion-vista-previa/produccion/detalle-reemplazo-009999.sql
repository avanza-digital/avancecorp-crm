-- SOLO LECTURA. Detalle del reemplazo de 2026-01-009999: la copia (original) y el contrato que quedó, con su PDF.
begin read only;
select 'copia (original)' as que, left(e.fuente_id::text, 8) as id, e.snapshot #>> '{inversion,capital}' as capital,
       e.snapshot #>> '{reemplazo,modo}' as modo, e.snapshot #>> '{reemplazo,dia_registro_venta}' as dia_venta,
       left(e.reemplazada_por::text, 8) as reemplazada_por, to_char(e.eliminado_en at time zone 'America/Lima', 'HH24:MI:SS') as hora,
       null::text as pdf, null::text as fecha_comercial, left((e.snapshot -> 'inversion')::text, 200) as detalle
from crm.inversiones_eliminadas e
where e.snapshot #>> '{contrato,numero_contrato}' = '2026-01-009999'
union all
select 'contrato vivo', left(c.id::text, 8), c.capital::text, c.categoria, c.fuente_cierre_comercial, null,
       to_char(c.creado_en at time zone 'America/Lima', 'HH24:MI:SS'),
       (select string_agg(j.estado || ' ' || to_char(j.creado_en at time zone 'America/Lima', 'HH24:MI:SS'), ', ' order by j.creado_en)
          from private.contrato_pdf_jobs j where j.contrato_id = c.id),
       c.fecha_cierre_comercial::text, 'analista ' || left(c.analista_cierre_id::text, 8) || ' · inicio ' || c.fecha_inicio
from public.contratos c where c.numero_contrato = '2026-01-009999';
rollback;
