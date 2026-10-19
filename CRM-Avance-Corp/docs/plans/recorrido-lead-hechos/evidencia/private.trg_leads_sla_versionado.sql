CREATE OR REPLACE FUNCTION private.trg_leads_sla_versionado()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  v_en timestamptz;
  v_p crm.sla_politicas%rowtype;
  v_maximo integer;
  v_n integer;
  v_motivo text;
begin
  v_en:=case when tg_op='INSERT' then new.sla_global_iniciado_en else statement_timestamp() end;
  perform set_config('crm.sla_writer','on',true);

  -- B8: el contacto de una base cargada que nace DORMIDO no abre ciclo (no «llegó»: no hay primera gestión ni primer
  -- contacto que medir y crm.metricas_sla_fn lo contaría fuera de objetivo). Su primer ciclo nace al reactivarlo.
  if (tg_op='INSERT' and not private.bases_carga_nace_dormido(new.origen,new.etapa,new.motivo_descarte,new.activo))
     or (tg_op='UPDATE' and new.ciclo_actual is distinct from old.ciclo_actual) then
    select p.* into v_p from crm.sla_politicas p
    where p.id=private.sla_politica_vigente(new.sla_global_iniciado_en);
    if not found then raise exception 'No existe politica SLA para el ciclo'; end if;
    insert into crm.lead_sla_ciclos(
      lead_id,ciclo_n,politica_id,iniciado_en,primera_gestion_limite_en,primer_contacto_limite_en
    ) values(new.id,new.ciclo_actual,v_p.id,new.sla_global_iniciado_en,
      new.sla_global_iniciado_en+v_p.primera_gestion_minutos*interval '1 minute',
      new.sla_global_iniciado_en+v_p.primer_contacto_minutos*interval '1 minute');
  end if;

  if tg_op='UPDATE' and (
    new.ciclo_actual is distinct from old.ciclo_actual or new.etapa is distinct from old.etapa
    or (old.activo and not new.activo)
  ) then
    v_motivo:=case
      when new.ciclo_actual is distinct from old.ciclo_actual then 'reapertura'
      when old.activo and not new.activo then 'desactivacion'
      when new.etapa in ('convertido','descartado') then 'cierre_terminal'
      else 'cambio_etapa' end;
    update crm.lead_sla_etapas set finalizado_en=v_en,motivo_cierre=v_motivo
    where lead_id=new.id and finalizado_en is null;
  end if;

  if new.activo and new.etapa in ('nuevo','contactado','reunion_agendada','propuesta_enviada')
    and (tg_op='INSERT' or new.ciclo_actual is distinct from old.ciclo_actual
      or new.etapa is distinct from old.etapa or (not old.activo and new.activo)) then
    select p.* into v_p
    from crm.sla_politicas p
    where p.id=private.sla_politica_vigente(v_en);
    if not found then raise exception 'No existe politica SLA vigente'; end if;
    select pe.maximo_minutos into v_maximo
    from crm.sla_politica_etapas pe
    where pe.politica_id=v_p.id and pe.etapa=new.etapa;
    if not found then raise exception 'No existe SLA para etapa %',new.etapa; end if;
    select coalesce(max(e.episodio_n),0)+1 into v_n from crm.lead_sla_etapas e
    where e.lead_id=new.id and e.ciclo_n=new.ciclo_actual;
    insert into crm.lead_sla_etapas(
      lead_id,ciclo_n,episodio_n,etapa,politica_id,iniciado_en,limite_en
    ) values(new.id,new.ciclo_actual,v_n,new.etapa,v_p.id,v_en,
      v_en+v_maximo*interval '1 minute');
  end if;
  perform set_config('crm.sla_writer','off',true);
  return new;
end;
$function$
