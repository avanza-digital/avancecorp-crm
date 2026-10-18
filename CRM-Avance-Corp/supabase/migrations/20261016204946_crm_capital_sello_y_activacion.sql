-- Sello atómico y activación explícita. Instalar no activa ni programa cron.
begin;
set local lock_timeout='5s';
set local statement_timeout='90s';
select pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados')::bigint);

do $$ begin
  if (select md5(prosrc) from pg_proc where oid='crm.cerrar_periodo(date)'::regprocedure)
    is distinct from '3289a365b8d9f4732272bba2a832e6a0' then
    raise exception 'Cambió cerrar_periodo: revisar el punto de integración antes de instalar';
  end if;
end $$;

alter table crm.capital_valoracion_politica add column activada_en timestamptz,
  add column bundle_compatible text,add column censo_huella text;

-- También protege altas del portal, cuyos escritores no toman advisory locks.
-- Se usa solo al activar o sellar, nunca para una consulta del navegador.
create function private.bloquear_fuentes_capital()
returns void language plpgsql security definer set search_path='' as $$ begin
  if current_setting('transaction_isolation')<>'read committed' then
    raise exception 'Activar o sellar capital requiere READ COMMITTED' using errcode='0A000';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados')::bigint);
  lock table public.contratos,crm.cierres_externos,crm.inversiones,crm.operaciones_cartera,
    crm.inversion_ajustes_mes_cerrado,crm.leads,crm.equipo,crm.meta_periodos,
    crm.metas_vendedor,crm.metas_vendedor_detalle,crm.ajustes_mes_cerrado in share mode;
end $$;
alter function private.bloquear_fuentes_capital() owner to postgres;
revoke all on function private.bloquear_fuentes_capital() from public,anon,authenticated,service_role;

create function private.validar_datos_capital_valorado()
returns void language plpgsql stable security definer set search_path='' as $$ begin
  -- ATR-4: la anulación descuenta conversión, conserva capital. No inventar
  -- un TC para deudas monetarias antiguas cuya correspondencia no esté resuelta.
  if exists(select 1 from crm.ajustes_mes_cerrado a where a.saldado_en is null
    and (a.pendiente_pen<>0 or a.pendiente_usd<>0 or exists(
      select 1 from jsonb_array_elements(a.pendiente_detalle) d where coalesce((d->>'capital')::numeric,0)<>0))) then
    raise exception 'Hay ajustes monetarios sin correspondencia valorada; resolver el origen antes de activar o sellar'
      using errcode='PT409';
  end if;
  if exists(select 1 from crm.metas_vendedor_detalle d join crm.metas_vendedor m on m.id=d.meta_vendedor_id
    join crm.meta_periodos p on p.id=m.meta_periodo_id
    where p.periodo>=date '2026-10-01' and d.moneda='USD' and d.capital_objetivo<>0
      and p.revision=(select max(q.revision) from crm.meta_periodos q where q.periodo=p.periodo)) then
    raise exception 'Las metas de capital deben estar en PEN; hay un objetivo USD sin equivalente fijado'
      using errcode='PT409';
  end if;
  if exists(select 1 from crm.operaciones_cartera o join public.contratos c on c.id=o.contrato_nuevo_id
    where c.fecha_cierre_comercial>=date '2026-10-01'
      and (o.fecha_operacion is distinct from c.fecha_cierre_comercial
        or o.periodo is distinct from date_trunc('month',c.fecha_cierre_comercial)::date)) then
    raise exception 'Un desglose contradice la fecha o periodo del contrato; conciliar antes de activar o sellar'
      using errcode='PT409';
  end if;
end $$;
alter function private.validar_datos_capital_valorado() owner to postgres;
revoke all on function private.validar_datos_capital_valorado() from public,anon,authenticated,service_role;

create function private.capital_censo_huella()
returns text language sql stable security definer set search_path='' as $$
  select md5(jsonb_build_array(
    (select coalesce(jsonb_agg(to_jsonb(b) order by b.fuente,b.fuente_id),'[]')
      from private.capital_operaciones_base('2026-10-01 America/Lima','infinity') b),
    (select coalesce(jsonb_agg(to_jsonb(m) order by m.periodo,m.revision),'[]')
      from crm.meta_periodos m where m.periodo>=date '2026-10-01'),
    (select coalesce(jsonb_agg(to_jsonb(d) order by d.meta_vendedor_id,d.categoria,d.moneda),'[]')
      from crm.metas_vendedor_detalle d join crm.metas_vendedor m on m.id=d.meta_vendedor_id
      join crm.meta_periodos p on p.id=m.meta_periodo_id where p.periodo>=date '2026-10-01'),
    (select coalesce(jsonb_agg(jsonb_build_array(v.fuente,v.fuente_id,v.revision,v.valoracion_id) order by v.fuente,v.fuente_id),'[]')
      from private.capital_valoraciones_actuales('2026-10-01 America/Lima','infinity') v)
  )::text);
$$;
alter function private.capital_censo_huella() owner to postgres;
revoke all on function private.capital_censo_huella() from public,anon,authenticated,service_role;

create function crm.preflight_capital_valorado_fn()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_pendientes integer;
begin
  perform private.validar_datos_capital_valorado();
  select count(*) into v_pendientes from private.capital_valoraciones_actuales('2026-10-01 America/Lima','infinity')
    where valoracion_id is null;
  return jsonb_build_object('huella',private.capital_censo_huella(),'pendientes',v_pendientes,
    'activa',(select activa from crm.capital_valoracion_politica where id),
    'sellos_incompatibles',(select count(*) from crm.periodos_cerrados p
      where p.periodo>=date '2026-10-01' and not exists(select 1 from crm.capital_mes_sellos s where s.periodo=p.periodo)));
end $$;
alter function crm.preflight_capital_valorado_fn() owner to postgres;
revoke all on function crm.preflight_capital_valorado_fn() from public,anon,authenticated;
grant execute on function crm.preflight_capital_valorado_fn() to service_role;

create function crm.activar_capital_valorado_fn(p_bundle text,p_huella text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_estado jsonb; v_periodo date;
begin
  if coalesce(p_bundle,'')!~ '^build-[A-Za-z0-9._-]{8,100}$' or coalesce(p_huella,'')!~ '^[0-9a-f]{32}$' then
    raise exception 'Se requiere bundle compatible publicado y huella de preflight' using errcode='22023';
  end if;
  perform private.bloquear_fuentes_capital();
  v_estado:=crm.preflight_capital_valorado_fn();
  if v_estado->>'huella'<>p_huella or (v_estado->>'pendientes')::integer<>0
    or (v_estado->>'sellos_incompatibles')::integer<>0 then
    raise exception 'Cambió el censo, faltan valoraciones o hay un mes con sello incompatible; repetir el preflight'
      using errcode='PT409';
  end if;
  for v_periodo in select d::date from generate_series(timestamp '2026-10-01',
    date_trunc('month',statement_timestamp() at time zone 'America/Lima'),interval '1 month') d loop
    perform private.publicar_corte_capital(v_periodo);
  end loop;
  update crm.capital_valoracion_politica set activa=true,
    activada_en=coalesce(activada_en,statement_timestamp()),bundle_compatible=p_bundle,censo_huella=p_huella where id;
  return jsonb_build_object('activa',true,'bundle',p_bundle,'huella',p_huella);
end $$;
alter function crm.activar_capital_valorado_fn(text,text) owner to postgres;
revoke all on function crm.activar_capital_valorado_fn(text,text) from public,anon,authenticated;
grant execute on function crm.activar_capital_valorado_fn(text,text) to service_role;

create function crm.suspender_capital_valorado_fn()
returns jsonb language plpgsql security definer set search_path='' as $$ begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados')::bigint);
  update crm.capital_valoracion_politica set activa=false where id;
  return jsonb_build_object('activa',false,'sellos_conservados',true);
end $$;
alter function crm.suspender_capital_valorado_fn() owner to postgres;
revoke all on function crm.suspender_capital_valorado_fn() from public,anon,authenticated;
grant execute on function crm.suspender_capital_valorado_fn() to service_role;

create function private.preparar_sello_capital(p_periodo date)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid; v_corte date; v_resultado jsonb; v_vueltas integer:=0;
begin
  if p_periodo<date '2026-10-01' or not(select activa from crm.capital_valoracion_politica where id) then return null; end if;
  perform private.bloquear_fuentes_capital();
  perform private.validar_datos_capital_valorado();
  loop
    v_resultado:=private.materializar_capital_valoraciones(500);
    exit when (v_resultado->>'creadas')::integer=0;
    v_vueltas:=v_vueltas+1;
    if v_vueltas>=200 then
      raise exception 'Completar la reconciliación antes de sellar un mes con más de 100 000 revisiones pendientes'
        using errcode='PT409';
    end if;
  end loop;
  v_id:=private.publicar_corte_capital(p_periodo);
  select corte into v_corte from crm.capital_cortes_valorados where id=v_id;
  if v_corte is distinct from (p_periodo+interval '1 month - 1 day')::date
    or exists(select 1 from private.capital_valoraciones_actuales(
      p_periodo::timestamp at time zone 'America/Lima',
      (p_periodo+interval '1 month')::timestamp at time zone 'America/Lima') where valoracion_id is null) then
    raise exception 'Cierre pendiente: falta una valoración consolidada de capital; se conserva el mes entero abierto'
      using errcode='PT409';
  end if;
  return v_id;
end $$;
alter function private.preparar_sello_capital(date) owner to postgres;
revoke all on function private.preparar_sello_capital(date) from public,anon,authenticated,service_role;

-- Se engancha antes de calcular conversión, aplicar deudas y escribir fotos.
-- La excepción revierte TODO el mes; ciclo_cierre_mes ya conserva su reintento.
do $integrar$
declare v_src text; v_ancla text:=E'  v_ini := p_periodo::timestamp at time zone ''America/Lima'';';
begin
  select prosrc into strict v_src from pg_proc where oid='crm.cerrar_periodo(date)'::regprocedure;
  if (length(v_src)-length(replace(v_src,v_ancla,'')))/length(v_ancla)<>1 then
    raise exception 'No coincide el ancla del cierre mensual';
  end if;
  v_src:=replace(v_src,v_ancla,E'  perform private.preparar_sello_capital(p_periodo);\n\n'||v_ancla);
  execute format('create or replace function crm.cerrar_periodo(p_periodo date) returns jsonb
    language plpgsql security definer set search_path='''' as %L',v_src);
end $integrar$;

create function private.capital_fijar_sello_trg()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
  v_id:=private.preparar_sello_capital(new.periodo);
  if v_id is not null then insert into crm.capital_mes_sellos(periodo,corte_id) values(new.periodo,v_id); end if;
  return new;
end $$;
alter function private.capital_fijar_sello_trg() owner to postgres;
revoke all on function private.capital_fijar_sello_trg() from public,anon,authenticated,service_role;
create trigger trg_capital_fijar_sello after insert on crm.periodos_cerrados
  for each row execute function private.capital_fijar_sello_trg();

-- La política vigente publica una meta mensual PEN. Bloquear una nueva meta
-- USD evita reintroducir conversión con la tasa de consulta por otro escritor.
create function private.capital_meta_pen_trg()
returns trigger language plpgsql security definer set search_path='' as $$ begin
  if new.moneda='USD' and new.capital_objetivo<>0
    and (select activa from crm.capital_valoracion_politica where id)
    and exists(select 1 from crm.metas_vendedor m join crm.meta_periodos p on p.id=m.meta_periodo_id
      where m.id=new.meta_vendedor_id and p.periodo>=date '2026-10-01') then
    raise exception 'La meta comercial se publica en soles; un objetivo USD requiere fijar su equivalente al publicar'
      using errcode='22023';
  end if;
  return new;
end $$;
alter function private.capital_meta_pen_trg() owner to postgres;
revoke all on function private.capital_meta_pen_trg() from public,anon,authenticated,service_role;
create trigger trg_capital_meta_pen before insert or update on crm.metas_vendedor_detalle
  for each row execute function private.capital_meta_pen_trg();

comment on table crm.capital_mes_sellos is
  'Extensión inmutable del sello mensual. Conserva el corte, las valoraciones de origen, metas e importes exactos sin ampliar el contrato estricto de las RPC v1.';
commit;
