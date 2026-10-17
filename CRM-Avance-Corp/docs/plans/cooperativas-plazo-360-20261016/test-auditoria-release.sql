\set ON_ERROR_STOP on
begin;
do $mutantes$
declare detectado boolean; n integer:=0;
begin
  detectado:=false;
  begin
    alter policy actividades_select on crm.actividades using (true);
    perform private.assert_actividades_de_lead();
  exception when raise_exception then
    if sqlerrm not like 'actividades_select cambio desde la auditoria%' then raise; end if;
    detectado:=true;
  end;
  if not detectado then raise exception 'Mutante actividades_select no detectado'; end if;
  n:=n+1;
  detectado:=false;
  begin
    alter policy leads_select on crm.leads using (true);
    perform private.assert_actividades_de_lead();
  exception when raise_exception then
    if sqlerrm not like 'leads_select cambio desde la auditoria%' then raise; end if;
    detectado:=true;
  end;
  if not detectado then raise exception 'Mutante leads_select no detectado'; end if;
  n:=n+1;
  detectado:=false;
  begin
    create policy auditoria_mutante_extra on crm.actividades for select to authenticated using (false);
    perform private.assert_actividades_de_lead();
  exception when raise_exception then
    if sqlerrm not like 'crm.actividades tiene otras permisivas de lectura%' then raise; end if;
    detectado:=true;
  end;
  if not detectado then raise exception 'Mutante conjunto permisivas no detectado'; end if;
  n:=n+1;
  detectado:=false;
  begin
    drop policy crm_actor_activo_gate on crm.actividades;
    perform private.assert_actividades_de_lead();
  exception when raise_exception then
    if sqlerrm not like 'Falta la restrictiva crm_actor_activo_gate%' then raise; end if;
    detectado:=true;
  end;
  if not detectado then raise exception 'Mutante restrictiva ausente no detectado'; end if;
  n:=n+1;
  raise notice 'PASS: % mutantes de seguridad detectados',n;
end;
$mutantes$;
rollback;
select private.assert_actividades_de_lead(),private.assert_gestion_diaria_registro();
