-- Valores iniciales versionados del repositorio, no filas de clientes/copias.
-- 20260807203757 (SLA), 20260816221500 (abandono), SLA-R2 en modo legado.
begin;
with p as (
  insert into crm.sla_politicas(version,vigente_desde,zona_horaria,tipo_reloj,
    primera_gestion_minutos,primer_contacto_minutos)
  select 1,'-infinity','America/Lima','corrido',1440,1440
  where not exists(select 1 from crm.sla_politicas)
  returning id
)
insert into crm.sla_politica_etapas(politica_id,etapa,maximo_minutos)
select p.id,x.etapa,x.minutos from p cross join (values
  ('nuevo'::text,1440),('contactado',4320),
  ('reunion_agendada',4320),('propuesta_enviada',7200)
) x(etapa,minutos);
insert into crm.politica_abandono(singleton,dias_abandono,dias_auto_bolsa)
select true,7,7 where not exists(select 1 from crm.politica_abandono);
-- La fila inicial se creó ANTES del trigger en su migración. El comando sólo
-- permite UPDATE, por lo que no puede reconstruir una base vacía. Reproducimos
-- esa única inserción en el banco sin desactivar auditoría ni tocar funciones;
-- el guardia se restituye y se verifica dentro de la misma transacción.
do $control_inicial$
declare v_trigger name;
begin
  if not exists(select 1 from crm.sla_operacion_control) then
    if exists(select 1 from crm.leads) then raise exception 'Control inicial requiere banco sin leads'; end if;
    select tgname into strict v_trigger from pg_trigger
    where tgrelid='crm.sla_operacion_control'::regclass
      and tgfoid='private.trg_sla_nucleo_entrada_guard()'::regprocedure
      and (tgtype::integer & 4)=4 and tgenabled='O';
    execute format('alter table crm.sla_operacion_control disable trigger %I',v_trigger);
    insert into crm.sla_operacion_control(id,modo) values(true,'legado');
    execute format('alter table crm.sla_operacion_control enable trigger %I',v_trigger);
    if (select tgenabled from pg_trigger where tgrelid='crm.sla_operacion_control'::regclass
      and tgname=v_trigger) <> 'O' then raise exception 'Guardia no restaurado'; end if;
  end if;
end $control_inicial$;
commit;
