-- TC comercial por venta: persistencia inmutable y cola de consolidación.
-- La política nace desactivada. Las lecturas antiguas y public no se alteran.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

select pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados')::bigint);
do $$ begin
  if exists(select 1 from crm.periodos_cerrados where periodo >= date '2026-10-01') then
    raise exception 'Hay meses desde octubre sellados; revisar la activación sin reescribir sus fotos';
  end if;
end $$;

create table crm.capital_valoracion_politica (
  id boolean primary key default true check(id),
  vigente_desde date not null default date '2026-10-01' check(vigente_desde=date '2026-10-01'),
  activa boolean not null default false,
  politica text not null default 'sbs_punto_medio_7d_v1' check(politica='sbs_punto_medio_7d_v1')
);
alter table crm.capital_valoracion_politica enable row level security;
insert into crm.capital_valoracion_politica(id) values(true);

create table crm.tipo_cambio_diario (
  fecha_corte date not null,
  politica text not null check(politica in('sbs_punto_medio_7d_v1','sbs_punto_medio_hasta7_legado_v1')),
  tasa numeric(14,4) not null check(tasa>0 and tasa<'Infinity'::numeric),
  pares jsonb not null check(jsonb_typeof(pares)='array' and
    ((politica='sbs_punto_medio_7d_v1' and jsonb_array_length(pares)=7)
      or (politica='sbs_punto_medio_hasta7_legado_v1' and jsonb_array_length(pares) between 1 and 7))),
  publicacion_confirmada date not null check(publicacion_confirmada>=fecha_corte),
  fuente text not null check(fuente='BCRP · SBS PD04639PD/PD04640PD'),
  huella_respuestas text not null check(huella_respuestas ~ '^[a-f0-9]{64}$'),
  consolidado_en timestamptz not null default statement_timestamp(),
  primary key(fecha_corte,politica)
);
alter table crm.tipo_cambio_diario enable row level security;

create table crm.capital_valoraciones (
  id uuid primary key default gen_random_uuid(),
  fuente text not null check(fuente in('contrato','cierre_externo')),
  fuente_id uuid not null,
  revision integer not null check(revision>0),
  anterior_id uuid references crm.capital_valoraciones(id),
  firma_fuente text not null,
  fecha_comercial date not null,
  monto numeric(20,2) not null check(monto>=0 and monto<'Infinity'::numeric),
  moneda text not null check(moneda in('PEN','USD')),
  fecha_tc date,
  politica_tc text,
  tasa numeric(14,4) not null check(tasa>0 and tasa<'Infinity'::numeric),
  equivalente_pen numeric(24,2) not null check(equivalente_pen>=0 and equivalente_pen<'Infinity'::numeric),
  motivo text not null check(motivo in('historica','nueva','correccion','reconstruida_legada')),
  creado_en timestamptz not null default statement_timestamp(),
  unique(fuente,fuente_id,revision),
  foreign key(fecha_tc,politica_tc) references crm.tipo_cambio_diario(fecha_corte,politica),
  check((moneda='PEN' and tasa=1 and fecha_tc is null and politica_tc is null and equivalente_pen=monto)
    or (moneda='USD' and fecha_tc is not null and politica_tc is not null
      and equivalente_pen=round(monto*tasa,2)))
);
alter table crm.capital_valoraciones enable row level security;
create index capital_valoraciones_fuente_actual on crm.capital_valoraciones(fuente,fuente_id,revision desc);

create table crm.tipo_cambio_trabajos (
  fecha_corte date not null,
  politica text not null default 'sbs_punto_medio_7d_v1' check(politica in('sbs_punto_medio_7d_v1','sbs_punto_medio_hasta7_legado_v1')),
  intentos integer not null default 0 check(intentos>=0),
  proximo_intento_en timestamptz not null default statement_timestamp(),
  reserva uuid,
  reservada_hasta timestamptz,
  completado_en timestamptz,
  ultimo_motivo text check(char_length(ultimo_motivo)<=300),
  creado_en timestamptz not null default statement_timestamp(),
  primary key(fecha_corte,politica),
  check((reserva is null)=(reservada_hasta is null))
);
alter table crm.tipo_cambio_trabajos enable row level security;
create index tipo_cambio_trabajos_pendientes on crm.tipo_cambio_trabajos(proximo_intento_en)
  where completado_en is null;

create function private.capital_tc_inmutable() returns trigger
language plpgsql set search_path='' as $$ begin
  raise exception 'La tasa o valoración consolidada es inmutable; registra una nueva revisión' using errcode='42501';
end $$;
revoke all on function private.capital_tc_inmutable() from public,anon,authenticated,service_role;
create trigger trg_tipo_cambio_diario_inmutable before update or delete on crm.tipo_cambio_diario
  for each row execute function private.capital_tc_inmutable();
create trigger trg_capital_valoraciones_inmutables before update or delete on crm.capital_valoraciones
  for each row execute function private.capital_tc_inmutable();
create trigger trg_tipo_cambio_diario_sin_truncate before truncate on crm.tipo_cambio_diario
  for each statement execute function private.capital_tc_inmutable();
create trigger trg_capital_valoraciones_sin_truncate before truncate on crm.capital_valoraciones
  for each statement execute function private.capital_tc_inmutable();

create trigger trg_audit_tipo_cambio_diario after insert on crm.tipo_cambio_diario
  for each row execute function private.log_audit_crm();
create trigger trg_audit_capital_valoraciones after insert on crm.capital_valoraciones
  for each row execute function private.log_audit_crm();
create trigger trg_audit_capital_valoracion_politica after insert or update on crm.capital_valoracion_politica
  for each row execute function private.log_audit_crm();
create trigger trg_audit_tipo_cambio_trabajos after insert or update on crm.tipo_cambio_trabajos
  for each row execute function private.log_audit_crm();

-- Las tablas financieras siguen siendo la autoridad. Se proyectan únicamente
-- episodios stock; los desgloses nunca crean una segunda operación comercial.
create function private.capital_fuentes_tc()
returns table(fuente text,fuente_id uuid,fecha_comercial date,fecha_imputacion date,
  moneda text,monto numeric,firma_fuente text)
language sql stable security definer set search_path='' as $$
  select f.*,md5(jsonb_build_array(f.fuente,f.fuente_id,f.fecha_comercial,f.moneda,f.monto)::text)
  from (
    select 'contrato'::text as fuente,e.contrato_id as fuente_id,
      c.fecha_cierre_comercial as fecha_comercial,
      (e.fecha at time zone 'America/Lima')::date as fecha_imputacion,
      e.moneda,e.monto
    from private.capital_episodios('-infinity'::timestamptz,'infinity'::timestamptz,true,'{}'::uuid[]) e
    join public.contratos c on c.id=e.contrato_id
    where e.medida='stock' and e.contrato_id is not null
    union all
    select 'cierre_externo',e.cierre_externo_id,ce.fecha_comercial,
      (e.fecha at time zone 'America/Lima')::date,e.moneda,e.monto
    from private.capital_episodios('-infinity'::timestamptz,'infinity'::timestamptz,true,'{}'::uuid[]) e
    join crm.cierres_externos ce on ce.id=e.cierre_externo_id
    where e.medida='stock' and e.cierre_externo_id is not null
  ) f;
$$;
revoke all on function private.capital_fuentes_tc() from public,anon,authenticated,service_role;

create function private.consolidar_tc_venta(p_evidencia jsonb)
returns numeric language plpgsql security definer set search_path='' as $$
declare
  v_corte date; v_confirmada date; v_tasa numeric; v_existente numeric;
  v_pares jsonb; v_n integer; v_distintos integer; v_correctos boolean;
  v_politica text; v_vigente date;
begin
  select vigente_desde into strict v_vigente from crm.capital_valoracion_politica where id;
  v_politica:=p_evidencia->>'politica';
  if jsonb_typeof(p_evidencia) is distinct from 'object' or pg_column_size(p_evidencia)>16000
    or coalesce(v_politica,'') not in('sbs_punto_medio_7d_v1','sbs_punto_medio_hasta7_legado_v1')
    or p_evidencia->>'fuente' is distinct from 'BCRP · SBS PD04639PD/PD04640PD'
    or coalesce(p_evidencia->>'huella_respuestas','') !~ '^[a-f0-9]{64}$'
    or coalesce(p_evidencia->>'fecha_corte','') !~ '^\d{4}-\d{2}-\d{2}$'
    or coalesce(p_evidencia->>'publicacion_confirmada','') !~ '^\d{4}-\d{2}-\d{2}$'
    or jsonb_typeof(p_evidencia->'pares') is distinct from 'array' then
    raise exception 'Evidencia del BCRP inválida' using errcode='22023';
  end if;
  v_corte:=(p_evidencia->>'fecha_corte')::date;
  v_confirmada:=(p_evidencia->>'publicacion_confirmada')::date;
  if (v_politica='sbs_punto_medio_7d_v1' and v_corte<v_vigente)
    or (v_politica='sbs_punto_medio_hasta7_legado_v1' and v_corte>=v_vigente) then
    raise exception 'La política no corresponde a la fecha comercial' using errcode='22023';
  end if;
  if v_confirmada<v_corte or v_confirmada>(statement_timestamp() at time zone 'America/Lima')::date then
    raise exception 'Publicación del BCRP todavía no confirmada' using errcode='22023';
  end if;
  v_pares:=p_evidencia->'pares';
  if exists(select 1 from jsonb_array_elements(v_pares) p
    where jsonb_typeof(p) is distinct from 'object'
      or coalesce(p->>'fecha','') !~ '^\d{4}-\d{2}-\d{2}$'
      or (p->>'compra' is null and p->>'venta' is null)
      or (p->>'compra' is not null and p->>'compra' !~ '^\d{1,6}(\.\d{1,10})?$')
      or (p->>'venta' is not null and p->>'venta' !~ '^\d{1,6}(\.\d{1,10})?$')
      or (v_politica='sbs_punto_medio_7d_v1' and (p->>'compra' is null or p->>'venta' is null))) then
    raise exception 'Pares del BCRP inválidos' using errcode='22023';
  end if;
  select count(*),count(distinct (p->>'fecha')::date),
    bool_and((p->>'fecha')::date<=v_corte
      and (p->>'fecha')::date>=v_corte-case when v_politica='sbs_punto_medio_hasta7_legado_v1' then 16 else 64 end
      and (p->>'compra' is null or (p->>'compra')::numeric>0)
      and (p->>'venta' is null or (p->>'venta')::numeric>0)),
    round(avg(case when p->>'compra' is not null and p->>'venta' is not null
      then ((p->>'compra')::numeric+(p->>'venta')::numeric)/2
      else coalesce((p->>'compra')::numeric,(p->>'venta')::numeric) end),4)
    into v_n,v_distintos,v_correctos,v_tasa
  from jsonb_array_elements(v_pares) p;
  if v_n<>v_distintos or not coalesce(v_correctos,false)
    or (v_politica='sbs_punto_medio_7d_v1' and v_n<>7)
    or (v_politica='sbs_punto_medio_hasta7_legado_v1' and v_n not between 1 and 7) then
    raise exception 'La evidencia no cumple la cantidad/calidad de la política del corte' using errcode='22023';
  end if;
  insert into crm.tipo_cambio_diario(fecha_corte,politica,tasa,pares,publicacion_confirmada,fuente,huella_respuestas)
    values(v_corte,v_politica,v_tasa,v_pares,v_confirmada,
      'BCRP · SBS PD04639PD/PD04640PD',p_evidencia->>'huella_respuestas')
    on conflict(fecha_corte,politica) do nothing;
  select tasa into strict v_existente from crm.tipo_cambio_diario
    where fecha_corte=v_corte and politica=v_politica;
  -- Un reintento o una revisión externa nunca sustituyen la tasa ya aceptada.
  return v_existente;
end $$;
revoke all on function private.consolidar_tc_venta(jsonb) from public,anon,authenticated,service_role;

create function private.materializar_capital_valoraciones(p_limite integer default 200)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  f record; v_anterior crm.capital_valoraciones%rowtype; v_tasa numeric;
  v_creadas integer:=0; v_pendientes integer:=0;
  v_vigente date; v_fecha_tc date; v_politica text;
begin
  select vigente_desde into strict v_vigente from crm.capital_valoracion_politica where id;
  if p_limite is null or p_limite not between 1 and 500 then
    raise exception 'Límite inválido' using errcode='22023';
  end if;
  if exists(select 1 from private.capital_fuentes_tc() s
    group by s.fuente,s.fuente_id having count(*)<>1) then
    raise exception 'La fuente financiera tiene episodios stock duplicados; no se adivina su identidad'
      using errcode='23514';
  end if;
  -- Descubrir todas las fechas antes de limitar las materializaciones evita
  -- que muchos pendientes antiguos impidan descubrir las ventas recientes.
  insert into crm.tipo_cambio_trabajos(fecha_corte,politica)
  select distinct k.fecha_tc,k.politica from private.capital_fuentes_tc() s
  cross join lateral(select
    case when s.fecha_comercial>=v_vigente then s.fecha_comercial
      else (date_trunc('month',s.fecha_comercial)+interval '1 month - 1 day')::date end as fecha_tc,
    case when s.fecha_comercial>=v_vigente then 'sbs_punto_medio_7d_v1'
      else 'sbs_punto_medio_hasta7_legado_v1' end as politica) k
  where s.moneda='USD' and (s.fecha_comercial>=v_vigente or s.fecha_imputacion>=v_vigente)
    and s.fecha_comercial<=(statement_timestamp() at time zone 'America/Lima')::date
    and not exists(select 1 from crm.tipo_cambio_diario t
      where t.fecha_corte=k.fecha_tc and t.politica=k.politica)
  on conflict(fecha_corte,politica) do nothing;
  for f in
    select s.* from private.capital_fuentes_tc() s
    left join lateral(select v.firma_fuente from crm.capital_valoraciones v
      where v.fuente=s.fuente and v.fuente_id=s.fuente_id order by v.revision desc limit 1) actual on true
    where (s.fecha_comercial>=v_vigente or s.fecha_imputacion>=v_vigente)
      and s.fecha_comercial <= (statement_timestamp() at time zone 'America/Lima')::date
      and s.firma_fuente is distinct from actual.firma_fuente
    order by (s.moneda='PEN' or exists(select 1 from crm.tipo_cambio_diario t
      where t.fecha_corte=case when s.fecha_comercial>=v_vigente then s.fecha_comercial
        else (date_trunc('month',s.fecha_comercial)+interval '1 month - 1 day')::date end
        and t.politica=case when s.fecha_comercial>=v_vigente then 'sbs_punto_medio_7d_v1'
          else 'sbs_punto_medio_hasta7_legado_v1' end)) desc,
      s.fecha_comercial,s.fuente,s.fuente_id limit p_limite
  loop
    perform pg_catalog.pg_advisory_xact_lock(hashtext('crm.capital_valoraciones'),hashtext(f.fuente||f.fuente_id::text));
    -- El descubrimiento no autoriza a congelar una lectura que cambió durante
    -- una edición concurrente. Se bloquea/relee la fuente financiera; una
    -- fila en edición se retoma en el siguiente ciclo sin bloquear las demás.
    if f.fuente='contrato' then
      perform 1 from public.contratos c where c.id=f.fuente_id for share skip locked;
      if not found then continue; end if;
      select c.fecha_cierre_comercial,c.moneda,c.capital,c.fecha_cierre_comercial
        into f.fecha_comercial,f.moneda,f.monto,f.fecha_imputacion from public.contratos c where c.id=f.fuente_id;
    else
      perform 1 from crm.cierres_externos ce where ce.id=f.fuente_id for share skip locked;
      if not found then continue; end if;
      select ce.fecha_comercial,ce.moneda,ce.monto,coalesce(ce.fecha_imputacion,(ce.creado_en at time zone 'America/Lima')::date)
        into f.fecha_comercial,f.moneda,f.monto,f.fecha_imputacion from crm.cierres_externos ce where ce.id=f.fuente_id;
    end if;
    if f.fecha_comercial is null
      or f.fecha_comercial>(statement_timestamp() at time zone 'America/Lima')::date then
      v_pendientes:=v_pendientes+1;
      continue;
    end if;
    f.firma_fuente:=md5(jsonb_build_array(f.fuente,f.fuente_id,f.fecha_comercial,f.moneda,f.monto)::text);
    select * into v_anterior from crm.capital_valoraciones
      where fuente=f.fuente and fuente_id=f.fuente_id order by revision desc limit 1;
    if v_anterior.firma_fuente is not distinct from f.firma_fuente then continue; end if;
    if f.fecha_comercial<v_vigente and f.fecha_imputacion<v_vigente then continue; end if;
    v_fecha_tc:=case when f.fecha_comercial>=v_vigente then f.fecha_comercial
      else (date_trunc('month',f.fecha_comercial)+interval '1 month - 1 day')::date end;
    v_politica:=case when f.fecha_comercial>=v_vigente then 'sbs_punto_medio_7d_v1'
      else 'sbs_punto_medio_hasta7_legado_v1' end;
    if f.moneda='PEN' then v_tasa:=1;
    else
      select tasa into v_tasa from crm.tipo_cambio_diario
        where fecha_corte=v_fecha_tc and politica=v_politica;
      if v_tasa is null then
        insert into crm.tipo_cambio_trabajos(fecha_corte,politica) values(v_fecha_tc,v_politica)
          on conflict(fecha_corte,politica) do nothing;
        v_pendientes:=v_pendientes+1;
        continue;
      end if;
    end if;
    insert into crm.capital_valoraciones(fuente,fuente_id,revision,anterior_id,firma_fuente,
      fecha_comercial,monto,moneda,fecha_tc,politica_tc,tasa,equivalente_pen,motivo)
    values(f.fuente,f.fuente_id,coalesce(v_anterior.revision,0)+1,v_anterior.id,f.firma_fuente,
      f.fecha_comercial,f.monto,f.moneda,
      case when f.moneda='USD' then v_fecha_tc end,
      case when f.moneda='USD' then v_politica end,
      v_tasa,round(f.monto*v_tasa,2),
      case when v_anterior.id is not null then 'correccion'
        when f.fecha_comercial<v_vigente then 'reconstruida_legada'
        when f.fecha_comercial<(statement_timestamp() at time zone 'America/Lima')::date then 'historica' else 'nueva' end);
    v_creadas:=v_creadas+1;
  end loop;
  return jsonb_build_object('creadas',v_creadas,'pendientes',v_pendientes);
end $$;
revoke all on function private.materializar_capital_valoraciones(integer) from public,anon,authenticated,service_role;

create function crm.reconciliar_capital_valoraciones_fn(p_limite integer default 200)
returns jsonb language sql security definer set search_path='' as $$
  select private.materializar_capital_valoraciones(p_limite);
$$;
revoke all on function crm.reconciliar_capital_valoraciones_fn(integer) from public,anon,authenticated;
grant execute on function crm.reconciliar_capital_valoraciones_fn(integer) to service_role;

create function crm.tomar_fechas_tipo_cambio_fn(p_limite integer default 10)
returns table(fecha_corte date,politica text,reserva uuid)
language plpgsql security definer set search_path='' as $$ begin
  if p_limite is null or p_limite not between 1 and 20 then
    raise exception 'Límite inválido' using errcode='22023';
  end if;
  return query with candidatos as (
    select t.fecha_corte,t.politica from crm.tipo_cambio_trabajos t
    where t.completado_en is null and t.proximo_intento_en<=statement_timestamp()
      and (t.reservada_hasta is null or t.reservada_hasta<=statement_timestamp())
    order by t.proximo_intento_en,t.fecha_corte limit p_limite for update skip locked
  ) update crm.tipo_cambio_trabajos t set reserva=gen_random_uuid(),
      reservada_hasta=statement_timestamp()+interval '5 minutes',intentos=t.intentos+1
    from candidatos c where t.fecha_corte=c.fecha_corte and t.politica=c.politica
    returning t.fecha_corte,t.politica,t.reserva;
end $$;
revoke all on function crm.tomar_fechas_tipo_cambio_fn(integer) from public,anon,authenticated;
grant execute on function crm.tomar_fechas_tipo_cambio_fn(integer) to service_role;

create function crm.resolver_fecha_tipo_cambio_fn(p_fecha date,p_reserva uuid,p_evidencia jsonb default null,p_motivo text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare t crm.tipo_cambio_trabajos%rowtype; v_tasa numeric; v_demora integer;
begin
  select * into t from crm.tipo_cambio_trabajos
    where fecha_corte=p_fecha and reserva=p_reserva for update;
  if not found or p_reserva is null or t.reserva is distinct from p_reserva
    or t.reservada_hasta<=statement_timestamp() or t.completado_en is not null then
    raise exception 'Reserva vencida o no disponible' using errcode='PT409';
  end if;
  if p_evidencia is not null then
    if p_evidencia->>'fecha_corte' is distinct from p_fecha::text
      or p_evidencia->>'politica' is distinct from t.politica then
      raise exception 'El corte no corresponde a la reserva' using errcode='22023';
    end if;
    v_tasa:=private.consolidar_tc_venta(p_evidencia);
    update crm.tipo_cambio_trabajos set completado_en=statement_timestamp(),
      reserva=null,reservada_hasta=null,ultimo_motivo=null where fecha_corte=p_fecha and politica=t.politica;
    return jsonb_build_object('estado','consolidado','tasa',v_tasa);
  end if;
  v_demora:=case t.intentos when 1 then 1 when 2 then 5 when 3 then 15 else 60 end;
  update crm.tipo_cambio_trabajos set reserva=null,reservada_hasta=null,
    proximo_intento_en=statement_timestamp()+make_interval(mins=>v_demora),
    ultimo_motivo=left(coalesce(nullif(p_motivo,''),'publicacion_pendiente'),300)
    where fecha_corte=p_fecha and politica=t.politica;
  return jsonb_build_object('estado','pendiente','reintento_minutos',v_demora);
end $$;
revoke all on function crm.resolver_fecha_tipo_cambio_fn(date,uuid,jsonb,text) from public,anon,authenticated;
grant execute on function crm.resolver_fecha_tipo_cambio_fn(date,uuid,jsonb,text) to service_role;

-- Sin acceso directo, ni siquiera por servicio: solo los escritores acotados.
alter table crm.capital_valoracion_politica owner to postgres;
alter table crm.tipo_cambio_diario owner to postgres;
alter table crm.capital_valoraciones owner to postgres;
alter table crm.tipo_cambio_trabajos owner to postgres;
alter function private.capital_tc_inmutable() owner to postgres;
alter function private.capital_fuentes_tc() owner to postgres;
alter function private.consolidar_tc_venta(jsonb) owner to postgres;
alter function private.materializar_capital_valoraciones(integer) owner to postgres;
alter function crm.reconciliar_capital_valoraciones_fn(integer) owner to postgres;
alter function crm.tomar_fechas_tipo_cambio_fn(integer) owner to postgres;
alter function crm.resolver_fecha_tipo_cambio_fn(date,uuid,jsonb,text) owner to postgres;
revoke all on crm.capital_valoracion_politica,crm.tipo_cambio_diario,crm.capital_valoraciones,crm.tipo_cambio_trabajos
  from public,anon,authenticated,service_role;

comment on table crm.capital_valoraciones is
  'Equivalente comercial por operación y revisión, inmutable. No sustituye la fuente financiera ni su atribución.';
comment on table crm.tipo_cambio_diario is
  'Siete pares SBS guardados y promedio numeric consolidado por fecha comercial; sin refresco posterior.';

commit;
