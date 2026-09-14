-- Cierre administrativo con responsable y referencia explícitos, sin borrar historia.
begin isolation level read committed;
set local search_path='';
set local lock_timeout='5s';
set local statement_timeout='15s';
do $revertir_f8$
declare
  v_config constant jsonb := '__CONFIG_JSON__'::jsonb;
  v_responsable uuid := (v_config->>'responsable_id')::uuid;
  v_referencia text := v_config->>'referencia';
  v_motivo text;
begin
  if current_user<>'postgres' or auth.uid() is not null then
    raise exception 'Requiere ejecución administrativa sin suplantar una sesión';
  end if;
  if v_referencia is null or v_referencia !~ '^[A-Z0-9_-]{4,60}$'
    or not exists(select 1 from public.perfiles p join crm.equipo e on e.perfil_id=p.id
      where p.id=v_responsable and p.activo and e.activo and e.rol_crm='gerencia') then
    raise exception 'Falta responsable operativo vigente o referencia de cierre';
  end if;
  v_motivo:='Cierre F8 ref:'||v_referencia||'; responsable operativo declarado; ejecución administrativa Codex';
  perform pg_advisory_xact_lock(hashtext('crm_piloto_f8_control'));
  update crm.piloto_f8_control set activo=false,motivo=v_motivo,
    actualizado_por=v_responsable where singleton and activo;
  update crm.piloto_f8_miembros set activo=false,motivo=v_motivo,
    actualizado_por=v_responsable where activo;
end;
$revertir_f8$;
commit;
