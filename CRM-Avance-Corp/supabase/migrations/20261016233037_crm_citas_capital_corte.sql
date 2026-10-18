-- El ticket de Citas suma los mismos equivalentes por operación. Conserva sus
-- propias reglas: stock sin anulados, identidad canónica y ámbito con PII.
-- La puerta anterior y todo public permanecen intactos.
begin;
set local lock_timeout='5s';
set local statement_timeout='90s';
select pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados')::bigint);

do $$ begin
  if (select md5(prosrc) from pg_proc where oid='private.citas_gerencia_consulta(date,date)'::regprocedure)
    is distinct from '3dc1c5481ca9dc1a6c45dfab969a6a0b' then
    raise exception 'Cambió el lector de Citas: revisar permisos, población e identidad antes de integrar cortes';
  end if;
end $$;

-- La persona que divide el ticket pertenece al mismo corte que el importe.
-- Una vinculación/merge posterior podrá publicar otro corte completo, pero no
-- debe alterar el divisor de una foto pendiente o de un mes ya sellado.
create function private.citas_identidad_capital(p_cliente uuid,p_lead uuid,p_externo uuid)
returns text language sql stable security definer set search_path='' as $$
  with vinculo as (
    select l.id,l.inversionista_id from crm.leads l where l.perfil_id=p_cliente
    order by (l.etapa='convertido') desc,l.convertido_en desc nulls last,l.id limit 1
  )
  select coalesce(
    case when coalesce(lk.inversionista_id,v.inversionista_id,ce.inversionista_id) is not null then
      'persona:'||private.inversionista_canonica(coalesce(lk.inversionista_id,v.inversionista_id,ce.inversionista_id))::text end,
    (select 'persona:'||private.inversionista_canonica(i.id)::text from crm.inversionistas i
      where i.perfil_id=p_cliente order by 1 limit 1),
    'perfil:'||p_cliente::text,'lead:'||coalesce(p_lead,v.id)::text,'externo:'||p_externo::text)
  from (values(1)) semilla(n)
  left join vinculo v on true left join crm.leads lk on lk.id=p_lead
  left join crm.cierres_externos ce on ce.id=p_externo;
$$;
alter function private.citas_identidad_capital(uuid,uuid,uuid) owner to postgres;
revoke all on function private.citas_identidad_capital(uuid,uuid,uuid) from public,anon,authenticated,service_role;

do $identidad$
declare v_def text;
  v_ancla text:='jsonb_agg(to_jsonb(h) order by h.fuente,h.fuente_id)';
begin
  if (select md5(prosrc) from pg_proc where oid='private.publicar_corte_capital(date)'::regprocedure)
    is distinct from '36e7d2bb94e22987e3feaa82df6542c4' then
    raise exception 'Cambió el publicador: revisar el corte conjunto antes de fijar su identidad';
  end if;
  select pg_get_functiondef('private.publicar_corte_capital(date)'::regprocedure) into v_def;
  if (length(v_def)-length(replace(v_def,v_ancla,'')))/length(v_ancla)<>1 then
    raise exception 'No coincide la proyección base del corte';
  end if;
  execute replace(v_def,v_ancla,'jsonb_agg(to_jsonb(h)||jsonb_build_object(''identidad_persona'',private.citas_identidad_capital(h.cliente_id,h.lead_id,h.cierre_externo_id)) order by h.fuente,h.fuente_id)');
end $identidad$;

create function private.citas_capital_del_corte(p_ini timestamptz,p_fin timestamptz,p_corte uuid)
returns table(tipo text,medida text,contrato_id uuid,cierre_externo_id uuid,
  lead_id uuid,cliente_id uuid,analista_id uuid,registrado_por uuid,en_roster boolean,
  moneda text,monto numeric,categoria text,mes_comercial date,fecha timestamptz,
  fecha_vencimiento date,estado text,anulado boolean,
  equivalente_pen numeric,tasa numeric,fecha_comercial date,fecha_tc date,politica_tc text,identidad_persona text)
language sql stable security definer set search_path='' as $$
  select k.tipo,k.medida,k.contrato_id,k.cierre_externo_id,k.lead_id,k.cliente_id,
    k.analista_id,k.registrado_por,k.en_roster,k.moneda,k.monto,k.categoria,k.mes_comercial,
    k.fecha,k.fecha_vencimiento,k.estado,k.anulado,
    k.equivalente_pen,k.tasa,k.fecha_comercial,k.fecha_tc,k.politica_tc,k.identidad_persona
  from crm.capital_cortes_valorados c cross join lateral jsonb_to_recordset(c.base) k(
    tipo text,medida text,contrato_id uuid,cierre_externo_id uuid,
    lead_id uuid,cliente_id uuid,analista_id uuid,registrado_por uuid,en_roster boolean,
    moneda text,monto numeric,categoria text,mes_comercial date,fecha timestamptz,
    fecha_vencimiento date,estado text,anulado boolean,
    equivalente_pen numeric,tasa numeric,fecha_comercial date,fecha_tc date,politica_tc text,identidad_persona text)
  where c.id=p_corte and k.fecha>=p_ini and k.fecha<p_fin;
$$;
alter function private.citas_capital_del_corte(timestamptz,timestamptz,uuid) owner to postgres;
revoke all on function private.citas_capital_del_corte(timestamptz,timestamptz,uuid) from public,anon,authenticated,service_role;

-- Reutilizar íntegro el lector vigente, sustituyendo únicamente sus DOS fuentes
-- monetarias (población vinculada y capital). No adjuntar valoraciones al capital
-- vivo: una corrección pendiente mezclaría importe viejo con fecha/monto nuevos.
do $extraer$
declare v_src text;
  v_origen text:=E'private.capital_episodios(v_ini,\n      least(v_fin,((v_ahora at time zone ''America/Lima'')::date+1)::timestamp at time zone ''America/Lima''),\n      true,''{}''::uuid[])';
  v_destino text:=E'private.citas_capital_del_corte(v_ini,\n      least(v_fin,((v_ahora at time zone ''America/Lima'')::date+1)::timestamp at time zone ''America/Lima''),p_corte)';
  v_campos text:='''moneda'',k.moneda,''monto'',k.monto,''fecha'',k.fecha';
  v_persona text:=E'''identidad_persona'',coalesce(\n      case when coalesce(lk.inversionista_id,v.inversionista_id,ce.inversionista_id)';
begin
  select prosrc into strict v_src from pg_proc where oid='private.citas_gerencia_consulta(date,date)'::regprocedure;
  if (length(v_src)-length(replace(v_src,v_origen,'')))/length(v_origen)<>2
    or (length(v_src)-length(replace(v_src,v_campos,'')))/length(v_campos)<>1
    or (length(v_src)-length(replace(v_src,v_persona,'')))/length(v_persona)<>1 then
    raise exception 'No coinciden las anclas monetarias de Citas';
  end if;
  v_src:=replace(v_src,v_origen,v_destino);
  v_src:=replace(v_src,v_persona,replace(v_persona,'''identidad_persona'',coalesce(','''identidad_persona'',coalesce(k.identidad_persona,'));
  v_src:=replace(v_src,v_campos,v_campos||E',\n    ''equivalente_pen'',k.equivalente_pen,''tasa'',k.tasa,\n    ''fecha_comercial'',k.fecha_comercial,''fecha_tc'',k.fecha_tc,''politica_tc'',k.politica_tc');
  execute format('create function private.citas_gerencia_consulta_corte(p_desde date,p_hasta date,p_corte uuid) returns jsonb language plpgsql stable security definer set search_path='''' as %L',v_src);
end $extraer$;
alter function private.citas_gerencia_consulta_corte(date,date,uuid) owner to postgres;
revoke all on function private.citas_gerencia_consulta_corte(date,date,uuid) from public,anon,authenticated,service_role;

create function crm.citas_gerencia_consulta_v2_fn(p_desde date,p_hasta date)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_uid uuid:=(select auth.uid()); v_rol text:=private.rol_crm(v_uid); v_ids uuid[];
  v_id uuid; v_sello uuid; v_corte crm.capital_cortes_valorados%rowtype;
  v_payload jsonb; v_visibles jsonb; v_cobertura jsonb;
  v_ini timestamptz; v_fin timestamptz;
begin
  -- La misma puerta de identidades que v1; Directorio no recibe esta consulta.
  if v_uid is null or v_rol not in('gerencia','supervisor') then
    raise exception 'No autorizado' using errcode='42501';
  end if;
  v_ids:=array(select private.vendedor_ids_visibles(v_uid));
  if coalesce(cardinality(v_ids),0)=0 then raise exception 'No autorizado' using errcode='42501'; end if;
  if p_desde is null or p_hasta is null or p_desde>p_hasta
    or p_desde<>date_trunc('month',p_desde)::date
    or p_hasta<>(date_trunc('month',p_desde)+interval '1 month - 1 day')::date
    or p_desde<date '2000-01-01'
    or p_desde>((now() at time zone 'America/Lima')::date+interval '1 year')::date then
    raise exception 'Seleccione un mes válido' using errcode='22023';
  end if;
  select corte_id into v_sello from crm.capital_mes_sellos where periodo=p_desde;
  if p_desde<date '2026-10-01' or (v_sello is null and
    (select activa from crm.capital_valoracion_politica where id) is distinct from true) then
    return crm.citas_gerencia_consulta_fn(p_desde,p_hasta);
  end if;
  if v_sello is null and exists(select 1 from crm.periodos_cerrados where periodo=p_desde) then
    raise exception 'El mes fue sellado sin valoración por venta' using errcode='PT409';
  end if;
  select * into v_corte from crm.capital_cortes_valorados
    where periodo=p_desde and (v_sello is null or id=v_sello) order by revision desc limit 1;
  v_id:=v_corte.id;
  if exists(select 1 from jsonb_array_elements(v_corte.base) k where nullif(k->>'identidad_persona','') is null) then
    raise exception 'Falta publicar un corte con identidad de capital para Citas' using errcode='PT409';
  end if;
  v_payload:=private.citas_gerencia_consulta_corte(p_desde,p_hasta,v_id);
  if v_rol='gerencia' then
    v_payload:=v_payload||jsonb_build_object('testigo',private.citas_testigo_mes(p_desde,p_hasta));
  end if;
  v_ini:=p_desde::timestamp at time zone 'America/Lima';
  v_fin:=least((p_hasta+1)::timestamp at time zone 'America/Lima',
    ((now() at time zone 'America/Lima')::date+1)::timestamp at time zone 'America/Lima');
  -- Los pendientes se buscan en fuentes actuales, con EXACTAMENTE el ámbito y
  -- la elegibilidad de Citas, aunque aún no figuren en el último corte.
  select coalesce(jsonb_agg(jsonb_build_object('fuente',b.fuente,'fuente_id',b.fuente_id)),'[]')
    into v_visibles from private.capital_operaciones_base(v_ini,v_fin) b
    where not b.anulado and (v_rol='gerencia' or b.analista_id=any(v_ids));
  v_cobertura:=case when v_sello is not null then jsonb_build_object(
    'corte',v_corte.corte,'generado_en',v_corte.creado_en,'estado','completo',
    'pendientes',jsonb_build_object('cantidad',0,'pen',0,'usd',0),
    'por_incorporar',jsonb_build_object('cantidad',0,'pen',0,'usd',0),'ventas_pendientes','[]'::jsonb)
    else private.capital_estado_corte(p_desde,v_id,v_visibles) end;
  return jsonb_set(v_payload,'{gestion,valoracion}',jsonb_build_object(
    'version',1,'activa',true,'corte_id',v_id,'sellado',v_sello is not null,'cobertura',v_cobertura));
end;
$$;
alter function crm.citas_gerencia_consulta_v2_fn(date,date) owner to postgres;
revoke all on function crm.citas_gerencia_consulta_v2_fn(date,date) from public,anon,authenticated,service_role;
grant execute on function crm.citas_gerencia_consulta_v2_fn(date,date) to authenticated;
notify pgrst,'reload schema';
commit;
