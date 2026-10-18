-- SOLO LECTURA. Copias de inversiones eliminadas o reemplazadas en las últimas 3 horas (cualquier cliente).
begin read only;
select to_char(e.eliminado_en at time zone 'America/Lima', 'HH24:MI') as hora_lima, e.empresa, e.fuente_tipo,
       e.snapshot #>> '{contrato,numero_contrato}' as numero, p.nombre_completo as cliente,
       e.reemplazada_por is not null as es_reemplazo, e.motivo, e.rol_actor
from crm.inversiones_eliminadas e left join public.perfiles p on p.id = e.inversionista_id
where e.eliminado_en > now() - interval '3 hours'
order by e.eliminado_en desc
limit 10;
rollback;
