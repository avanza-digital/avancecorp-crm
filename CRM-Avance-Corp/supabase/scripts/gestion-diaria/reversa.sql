-- Reversa de Gestión Diaria · Fase 1 (registro crudo). Solo retira objetos
-- NUEVOS: nada se reemplazó, así que no hay definición anterior que restaurar.
-- Ejecutar solo tras retirar el front que llama a crm.registro_actividad_fn.
-- No toca datos. Idempotente.
begin;
set local lock_timeout = '5s';
drop function if exists private.assert_gestion_diaria_mutantes();
drop function if exists private.assert_gestion_diaria();
drop function if exists crm.registro_actividad_fn(date, date, uuid[], text[], text, integer, timestamptz, uuid);
drop function if exists private.registro_actividad_core(timestamptz, timestamptz, uuid[], text[], text, integer, timestamptz, uuid);
drop index if exists crm.actividades_autor_fecha_idx;
create index if not exists idx_actividades_creado_por on crm.actividades (creado_por);
do $reversa$
begin
  if to_regprocedure('crm.registro_actividad_fn(date,date,uuid[],text[],text,integer,timestamptz,uuid)') is not null
     or exists (select 1 from pg_indexes where schemaname = 'crm' and indexname = 'actividades_autor_fecha_idx') then
    raise exception 'REVERSA: quedaron objetos de Gestion Diaria';
  end if;
  -- Los gates del mundo SLA no dependen de esta migración: siguen en verde.
  perform private.assert_sla_nucleo();
  perform private.assert_sla_operacion();
  perform private.assert_sla_comandos();
  perform private.assert_sla_avisos();
end;
$reversa$;
notify pgrst, 'reload schema';
commit;
