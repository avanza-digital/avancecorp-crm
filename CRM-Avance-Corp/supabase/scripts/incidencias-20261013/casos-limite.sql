-- Casos límite de la proyección de tareas: NULL/infinity no son inserts CRM.
-- Los dos agregados provienen de las definiciones anterior y nueva ensayadas.
begin;
create temp table casos_limite as
with hechos as materialized (select generate_series(1,9) lead_id),
tareas as materialized (
 select t.*,null::text titulo,0 reprogramaciones,1 responsable_id,2 autor_id,
 null::text autor_nombre,'fixture'::text contexto_fuente
 from (values
 (2,1,'llamada','2026-10-13 10:00Z'::timestamptz,null::text),
 (2,2,'reunion','2026-10-13 10:00Z'::timestamptz,null::text),
 (3,3,'tarea','2026-10-13 10:00Z'::timestamptz,null::text),
 (4,4,'llamada','2026-10-13 10:00Z'::timestamptz,'contexto_tarea_ambiguo'),
 (5,5,'llamada','infinity'::timestamptz,null::text),
 (6,6,'llamada',null::timestamptz,null::text),
 (7,7,'whatsapp','2026-10-13 10:00Z'::timestamptz,'tenencia_tarea_incoherente'),
 (7,8,'whatsapp','2026-10-13 11:00Z'::timestamptz,null::text),
 (7,9,'reunion','2026-10-13 09:00Z'::timestamptz,'tenencia_tarea_incoherente'),
 (8,10,'tarea','2026-10-13 10:00Z'::timestamptz,'fecha_tarea_invalida'),
 (8,11,'reunion','2026-10-13 11:00Z'::timestamptz,null::text),
 (9,12,'tarea',null::timestamptz,'fecha_tarea_invalida')
 ) t(lead_id,tarea_id,tipo,vence_en,motivo_dato)
), nueva as materialized (
select t.lead_id, array_agg(distinct t.motivo_dato) filter (
          where t.tipo in ('llamada','whatsapp','reunion') and t.motivo_dato is not null) as motivos_tarea,
        (jsonb_agg(jsonb_build_object('id',t.tarea_id,'lead_id',t.lead_id,'tipo',t.tipo,
          'titulo',t.titulo,'vence_en',t.vence_en,'reprogramaciones',t.reprogramaciones,
          'responsable_id',t.responsable_id,'autor_id',t.autor_id,'autor_nombre',t.autor_nombre,
          'contexto_fuente',t.contexto_fuente) order by t.vence_en,t.tarea_id)
          filter (where t.tipo in ('llamada','whatsapp','reunion') and t.motivo_dato is null))->0 as primera_comercial,
        (jsonb_agg(jsonb_build_object('id',t.tarea_id,'tipo',t.tipo,'titulo',t.titulo,'vence_en',t.vence_en) order by t.vence_en,t.tarea_id)
          filter (where isfinite(t.vence_en) and t.motivo_dato is null))->0 as primera_agenda
      from tareas t group by t.lead_id
)
select h.lead_id,
 o.motivos_tarea is not distinct from n.motivos_tarea
 and o.primera_comercial is not distinct from n.primera_comercial
 and o.primera_agenda is not distinct from n.primera_agenda as iguales
from hechos h left join lateral (
      select array_agg(distinct t.motivo_dato) filter (
          where t.tipo in ('llamada','whatsapp','reunion') and t.motivo_dato is not null) as motivos_tarea,
        (jsonb_agg(jsonb_build_object('id',t.tarea_id,'lead_id',t.lead_id,'tipo',t.tipo,
          'titulo',t.titulo,'vence_en',t.vence_en,'reprogramaciones',t.reprogramaciones,
          'responsable_id',t.responsable_id,'autor_id',t.autor_id,'autor_nombre',t.autor_nombre,
          'contexto_fuente',t.contexto_fuente) order by t.vence_en,t.tarea_id)
          filter (where t.tipo in ('llamada','whatsapp','reunion') and t.motivo_dato is null))->0 as primera_comercial,
        (jsonb_agg(jsonb_build_object('id',t.tarea_id,'tipo',t.tipo,'titulo',t.titulo,'vence_en',t.vence_en) order by t.vence_en,t.tarea_id)
          filter (where isfinite(t.vence_en) and t.motivo_dato is null))->0 as primera_agenda
      from tareas t where t.lead_id=h.lead_id
) o on true left join nueva n on n.lead_id=h.lead_id;
do $test$ begin
 if (select count(*) from casos_limite where iguales)<>9 then raise exception 'Agregados distintos en caso límite'; end if;
end $test$;
select count(*) as casos_limite_iguales from casos_limite where iguales;
rollback;
