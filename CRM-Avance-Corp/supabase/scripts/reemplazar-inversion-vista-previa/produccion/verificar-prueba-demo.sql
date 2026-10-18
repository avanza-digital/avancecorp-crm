-- SOLO LECTURA. Estado de la prueba de «Reemplazar inversión» con el cliente DEMO DEMO DEMO (e3eb769a…): sus contratos
-- vivos (con analista, fecha comercial y PDF) y las copias de lo eliminado o reemplazado. Una sola tabla de salida.
begin read only;
with cli as (select p.id from public.perfiles p where p.rol = 'cliente' and p.id::text like 'e3eb769a%'),
vivos as (
  select 'vivo' as que, c.numero_contrato, c.capital::text, c.moneda, c.estado, c.categoria, c.fecha_inicio::text,
         c.fecha_cierre_comercial::text as fecha_comercial, c.fuente_cierre_comercial as fuente,
         left(c.analista_cierre_id::text, 8) as analista,
         coalesce((select j.estado from private.contrato_pdf_jobs j where j.contrato_id = c.id order by j.creado_en desc limit 1), '—') as pdf_job,
         (select count(*) from private.contrato_pdfs d where d.contrato_id = c.id)::text as pdfs_sellados,
         null::text as reemplazada_por, left(c.id::text, 8) as id_corto, c.creado_en
  from public.contratos c join cli on cli.id = c.cliente_id),
copias as (
  select case when e.reemplazada_por is not null then 'copia: reemplazada' else 'copia: eliminada' end, e.snapshot #>> '{contrato,numero_contrato}',
         e.snapshot #>> '{inversion,capital}', e.snapshot #>> '{inversion,moneda}', null, null, null,
         e.snapshot #>> '{reemplazo,dia_registro_venta}', null, null, null, null,
         coalesce(e.snapshot #>> '{reemplazo,numero_contrato}', '') || ' ' || coalesce(left(e.reemplazada_por::text, 8), ''),
         left(e.fuente_id::text, 8), e.eliminado_en
  from crm.inversiones_eliminadas e join cli on cli.id = e.inversionista_id)
select que, numero_contrato, capital, moneda, estado, categoria, fecha_inicio, fecha_comercial, fuente, analista, pdf_job,
       pdfs_sellados, reemplazada_por, id_corto
from (select * from vivos union all select * from copias) x order by creado_en;
rollback;
