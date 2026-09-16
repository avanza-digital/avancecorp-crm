-- Reversa operativa: apaga F4/F5/F6. Conserva inversiones, perfiles e historia.
-- No reactiva un piloto vencido ni modifica su ventana o participantes.
-- Un solo uso: reabrir después requiere otra captura, SQL y verificación.
begin isolation level read committed;
set local search_path='';
set local lock_timeout='3s';set local statement_timeout='30s';
do $f9_reversa$
declare cfg constant jsonb:='__CONFIG__'::jsonb;banderas jsonb;
begin
  if current_user<>'postgres' or auth.uid() is not null then
    raise exception 'Se requiere administración sin suplantación' using errcode='P0409';end if;
  perform pg_advisory_xact_lock(hashtext('crm_flag_resolver_en_puertas'));
  perform pg_advisory_xact_lock(hashtext('crm_flag_ficha_360_neutral'));
  perform pg_advisory_xact_lock(hashtext('crm_flag_inversiones_escritura'));
  perform pg_advisory_xact_lock(hashtext('crm_flag_postventa_neutral'));
  perform pg_advisory_xact_lock(hashtext('crm_piloto_f8_control'));
  if not exists(select 1 from crm.piloto_f8_control where singleton and not activo
    and motivo='Apertura general '||(cfg->>'referencia')||'; autorizada por Miguel; ejecución administrativa Codex') then
    raise exception 'La apertura registrada cambió; revisar reversa' using errcode='P0409';end if;
  select jsonb_object_agg(nombre,activo) into banderas from crm.multiempresa_flags;
  if banderas is distinct from '{"resolver_en_puertas":true,"inversiones_escritura":true,"ficha_360_neutral":true,"postventa_neutral":true,"metricas_multiempresa_sombra":false}'::jsonb then
    raise exception 'Configuración ajena al alcance de esta reversa' using errcode='P0409';end if;
  update crm.multiempresa_flags set activo=false,actualizado_por=(cfg->>'responsable_id')::uuid
    where nombre in('inversiones_escritura','ficha_360_neutral','postventa_neutral');
  update crm.piloto_f8_control set motivo='Reversa de apertura '||(cfg->>'referencia')||'; capacidades nuevas apagadas',
    actualizado_por=(cfg->>'responsable_id')::uuid where singleton;
end;
$f9_reversa$;
commit;
select jsonb_build_object('estado',case when not (select activo from crm.piloto_f8_control where singleton)
    and (select jsonb_object_agg(nombre,activo) from crm.multiempresa_flags)=
      '{"resolver_en_puertas":true,"inversiones_escritura":false,"ficha_360_neutral":false,"postventa_neutral":false,"metricas_multiempresa_sombra":false}'::jsonb
    then 'PASS' else 'FAIL' end,'accion','reversa','fecha',clock_timestamp(),'confirmado_despues_commit',true,
  'banderas',(select jsonb_object_agg(nombre,activo) from crm.multiempresa_flags)) evidencia;
