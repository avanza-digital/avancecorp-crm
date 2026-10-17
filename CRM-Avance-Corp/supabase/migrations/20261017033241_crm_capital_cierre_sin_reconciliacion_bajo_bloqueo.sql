-- El worker confirma revisiones antes del cierre. Nunca procesar un atraso
-- bajo los bloqueos globales que protegen la foto mensual.
begin;
set local lock_timeout='5s';
set local statement_timeout='90s';
select pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados')::bigint);

do $$ begin
  if (select md5(prosrc) from pg_proc where oid='private.preparar_sello_capital(date)'::regprocedure)
    is distinct from '5130c7577d6bc950d4bc6cf42c5ef182' then
    raise exception 'Cambió la preparación de sello: revisar antes de acotar el cierre';
  end if;
end $$;

create or replace function private.preparar_sello_capital(p_periodo date)
returns uuid language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare v_id uuid; v_corte date; v_pendientes bigint;
begin
  if p_periodo<date '2026-10-01' or not(select activa from crm.capital_valoracion_politica where id) then return null; end if;
  -- Precheck sin bloquear escrituras: la reconciliación pertenece al worker.
  select count(*) into v_pendientes from private.capital_valoraciones_actuales(
    p_periodo::timestamp at time zone 'America/Lima',
    (p_periodo+interval '1 month')::timestamp at time zone 'America/Lima') where valoracion_id is null;
  if v_pendientes>0 then
    raise exception 'Cierre pendiente: reconciliar % valoraciones de capital antes de sellar; el mes entero sigue abierto',v_pendientes
      using errcode='PT409',hint='Ejecutar el worker autorizado; comprobar cobertura y volver a evaluar el ciclo normal.';
  end if;
  perform private.bloquear_fuentes_capital();
  perform private.validar_datos_capital_valorado();
  -- Una venta/corrección pudo confirmar entre el precheck y el bloqueo.
  if exists(select 1 from private.capital_valoraciones_actuales(
    p_periodo::timestamp at time zone 'America/Lima',
    (p_periodo+interval '1 month')::timestamp at time zone 'America/Lima') where valoracion_id is null) then
    raise exception 'Cierre pendiente: cambió la cobertura de capital; reconciliar antes de reintentar'
      using errcode='PT409';
  end if;
  v_id:=private.publicar_corte_capital(p_periodo);
  select corte into v_corte from crm.capital_cortes_valorados where id=v_id;
  if v_corte is distinct from (p_periodo+interval '1 month - 1 day')::date then
    raise exception 'Cierre pendiente: falta una publicación completa de capital; el mes entero sigue abierto'
      using errcode='PT409';
  end if;
  return v_id;
end $$;
comment on function private.preparar_sello_capital(date) is
  'Exige reconciliación previa del worker, revalida cobertura bajo bloqueo y publica la foto completa. No materializa atrasos durante el cierre; espera de locks limitada a 5 s.';
commit;
