-- Advisor del ensayo hosted: cubrir la FK de la cita de oficina cuando crezca
-- el historial de actividades. El control administrativo tiene una sola fila.
begin;
set local search_path='';
set local lock_timeout='5s';
create index actividad_ciclo_contexto_oficina_tarea_idx
  on crm.actividad_ciclo_contexto(oficina_tarea_id);
do $$
begin
  if not exists(select 1 from pg_index i join pg_attribute a
      on a.attrelid=i.indrelid and a.attname='oficina_tarea_id'
      where i.indexrelid='crm.actividad_ciclo_contexto_oficina_tarea_idx'::regclass
        and i.indrelid='crm.actividad_ciclo_contexto'::regclass
        and i.indisvalid and i.indisready and i.indkey[0]=a.attnum) then
    raise exception 'El indice de la cita del recorrido no quedo operativo';
  end if;
  perform private.assert_sla_nucleo();
end $$;
commit;
