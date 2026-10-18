-- Solicitud de servicio posterior al commit de la reconciliación. El estado
-- del cron sigue siendo autoridad: esta puerta nunca lo configura/reactiva.
begin;
set local lock_timeout='5s';
set local statement_timeout='90s';

do $$ begin
  if (select md5(prosrc) from pg_proc where oid='crm.reconciliar_capital_valoraciones_fn(integer)'::regprocedure)
      is distinct from '15637d715193dc2505b292495f41b82f' then
    raise exception 'Cambió la reconciliación: revisar su contrato de avance antes de integrar el reintento';
  end if;
end $$;

-- Una venta puede haberse valorado en su escritor. Publicar ahora el corte
-- completo también representa avance aunque este lote cree cero valoraciones.
create or replace function crm.reconciliar_capital_valoraciones_fn(p_limite integer default 200)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_resultado jsonb; v_periodo date; v_cortes integer:=0; v_nuevos integer:=0; v_antes uuid; v_despues uuid;
begin
  v_resultado:=private.materializar_capital_valoraciones(p_limite);
  for v_periodo in select d::date from generate_series(
    (select vigente_desde::timestamp from crm.capital_valoracion_politica where id),
    date_trunc('month',statement_timestamp() at time zone 'America/Lima'),interval '1 month') d
  loop
    select id into v_antes from crm.capital_cortes_valorados where periodo=v_periodo order by revision desc limit 1;
    v_despues:=private.publicar_corte_capital(v_periodo);
    if v_despues is not null then v_cortes:=v_cortes+1; end if;
    if v_despues is distinct from v_antes then v_nuevos:=v_nuevos+1; end if;
  end loop;
  return v_resultado||jsonb_build_object('meses_con_corte',v_cortes,'cortes_publicados',v_nuevos);
end $$;

create function crm.reevaluar_cierre_capital_fn()
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='3s' as $$
declare v_cantidad integer; v_activo boolean; v_compatible boolean;
begin
  if (select auth.uid()) is not null then
    raise exception 'La reevaluación automática solo corresponde al servicio' using errcode='42501';
  end if;
  -- Suspensión, activación y cierre comparten el orden global -> fuentes.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados')::bigint);
  if (select activa from crm.capital_valoracion_politica where id) is distinct from true then
    return jsonb_build_object('evaluado',false,'motivo','politica_desactivada');
  end if;
  if pg_catalog.to_regclass('cron.job') is null then
    return jsonb_build_object('evaluado',false,'motivo','cron_no_configurado');
  end if;
  select count(*),bool_and(j.active),bool_and(j.command ~*
    '^[[:space:]]*select[[:space:]]+crm[.]ciclo_cierre_mes[[:space:]]*[(][[:space:]]*[)][[:space:]]*;?[[:space:]]*$')
    into v_cantidad,v_activo,v_compatible
  from cron.job j where j.jobname='crm-cierre-mes-diario' and j.database=current_database();
  if v_cantidad=0 then return jsonb_build_object('evaluado',false,'motivo','cron_no_configurado'); end if;
  if v_cantidad<>1 or v_compatible is distinct from true then
    return jsonb_build_object('evaluado',false,'motivo','cron_incompatible');
  end if;
  if v_activo is distinct from true then
    return jsonb_build_object('evaluado',false,'motivo','cron_pausado');
  end if;
  -- Es una lectura de autorización temporal: pausar después no cancela una
  -- ejecución ya aceptada, igual que el cron. No requiere UPDATE sobre cron.job.
  return jsonb_build_object('evaluado',true,'resultado',crm.ciclo_cierre_mes());
end $$;
alter function crm.reevaluar_cierre_capital_fn() owner to postgres;
revoke all on function crm.reevaluar_cierre_capital_fn() from public,anon,authenticated;
grant execute on function crm.reevaluar_cierre_capital_fn() to service_role;
comment on function crm.reevaluar_cierre_capital_fn() is
  'Solo servicio, después del commit de materialización. Reevalúa por el ciclo existente únicamente si su programación está activa y es compatible. Nunca configura cron ni fuerza un mes.';
commit;
