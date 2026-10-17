-- Una sola implementación monetaria para worker y escritores. No cambia
-- objetos de public ni publica cortes parciales durante una escritura.
begin;
set local lock_timeout='5s';
set local statement_timeout='90s';
select pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados')::bigint);

do $$ begin
  if (select md5(prosrc) from pg_proc where oid='private.materializar_capital_valoraciones(integer)'::regprocedure)
      is distinct from '8ddf7af128a1b801e513957bd24e1285'
    or (select md5(prosrc) from pg_proc where oid='private.inversion_vincular_fuente(uuid,uuid,uuid,uuid,boolean)'::regprocedure)
      is distinct from 'ea27a4671d5877c7185ceda842c18515'
    or (select md5(prosrc) from pg_proc where oid='crm.corregir_fecha_cierre_comercial(uuid,date,text)'::regprocedure)
      is distinct from 'c5d27f96168e9dc3546ff6cbc266c74f'
    or (select md5(prosrc) from pg_proc where oid='crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)'::regprocedure)
      is distinct from '22ec068ff5d27312c5eb0749600292fd' then
    raise exception 'Cambió un escritor o materializador: revisar transacciones y gates antes de integrar';
  end if;
end $$;

-- La proyección es la misma que usa el worker, con intervalo acotado para una
-- operación individual. No recorrer toda la historia por cada contrato.
do $fuente$
declare v_src text; v_ancla text:='private.capital_operaciones_base(''-infinity''::timestamptz,''infinity''::timestamptz)';
begin
  select prosrc into strict v_src from pg_proc where oid='private.capital_fuentes_tc()'::regprocedure;
  if (length(v_src)-length(replace(v_src,v_ancla,'')))/length(v_ancla)<>1
    or (length(v_src)-length(replace(v_src,' b;','')))/length(' b;')<>1 then
    raise exception 'La proyección de fuente canónica cambió';
  end if;
  v_src:=replace(v_src,v_ancla,'private.capital_operaciones_base(p_ini,p_fin)');
  v_src:=replace(v_src,' b;', ' b where (p_fuente is null or b.fuente=p_fuente and b.fuente_id=p_id);');
  execute format('create function private.capital_fuentes_tc_rango(p_ini timestamptz,p_fin timestamptz,p_fuente text,p_id uuid)
    returns table(fuente text,fuente_id uuid,fecha_comercial date,fecha_imputacion date,moneda text,monto numeric,firma_fuente text)
    language sql stable security definer set search_path='''' as %L',v_src);
end $fuente$;
alter function private.capital_fuentes_tc_rango(timestamptz,timestamptz,text,uuid) owner to postgres;
revoke all on function private.capital_fuentes_tc_rango(timestamptz,timestamptz,text,uuid) from public,anon,authenticated,service_role;

create or replace function private.capital_fuentes_tc()
returns table(fuente text,fuente_id uuid,fecha_comercial date,fecha_imputacion date,moneda text,monto numeric,firma_fuente text)
language sql stable security definer set search_path='' as $$
  select * from private.capital_fuentes_tc_rango('-infinity','infinity',null,null);
$$;

create function private.capital_fuentes_tc_para(p_fuente text,p_id uuid)
returns table(fuente text,fuente_id uuid,fecha_comercial date,fecha_imputacion date,moneda text,monto numeric,firma_fuente text)
language plpgsql stable security definer set search_path='' as $$
declare v_dia date;
begin
  if p_fuente is null and p_id is null then
    return query select * from private.capital_fuentes_tc();
    return;
  end if;
  if p_fuente is null or p_id is null or p_fuente not in('contrato','cierre_externo') then
    raise exception 'Identidad de valoración inválida' using errcode='22023';
  end if;
  if p_fuente='contrato' then
    select c.fecha_cierre_comercial into v_dia from public.contratos c where c.id=p_id;
  else
    select coalesce(c.fecha_imputacion,(c.creado_en at time zone 'America/Lima')::date)
      into v_dia from crm.cierres_externos c where c.id=p_id;
  end if;
  if not found then return; end if;
  return query select * from private.capital_fuentes_tc_rango(
    case when v_dia is null then '-infinity'::timestamptz else v_dia::timestamp at time zone 'America/Lima' end,
    case when v_dia is null then 'infinity'::timestamptz else (v_dia+1)::timestamp at time zone 'America/Lima' end,
    p_fuente,p_id);
end $$;
alter function private.capital_fuentes_tc_para(text,uuid) owner to postgres;
revoke all on function private.capital_fuentes_tc_para(text,uuid) from public,anon,authenticated,service_role;

-- Extraer el algoritmo probado sin duplicarlo. El wrapper de lote conserva
-- firma y permisos; las llamadas de escritor filtran fuente/id desde el inicio.
do $materializar$
declare v_src text; v_ancla text:='private.capital_fuentes_tc() s';
begin
  select prosrc into strict v_src from pg_proc where oid='private.materializar_capital_valoraciones(integer)'::regprocedure;
  if (length(v_src)-length(replace(v_src,v_ancla,'')))/length(v_ancla)<>3 then
    raise exception 'Cambió la lectura del materializador';
  end if;
  v_src:=replace(v_src,v_ancla,'private.capital_fuentes_tc_para(p_fuente,p_id) s');
  execute format('create function private.materializar_capital_valoraciones_para(p_limite integer,p_fuente text,p_id uuid)
    returns jsonb language plpgsql security definer set search_path='''' as %L',v_src);
end $materializar$;
alter function private.materializar_capital_valoraciones_para(integer,text,uuid) owner to postgres;
revoke all on function private.materializar_capital_valoraciones_para(integer,text,uuid) from public,anon,authenticated,service_role;
create or replace function private.materializar_capital_valoraciones(p_limite integer default 200)
returns jsonb language sql security definer set search_path='' as $$
  select private.materializar_capital_valoraciones_para(p_limite,null,null);
$$;

do $vincular$
declare v_src text; v_ancla text:='  return v_i.id;';
begin
  select prosrc into strict v_src from pg_proc where oid='private.inversion_vincular_fuente(uuid,uuid,uuid,uuid,boolean)'::regprocedure;
  if (length(v_src)-length(replace(v_src,v_ancla,'')))/length(v_ancla)<>1 then
    raise exception 'Cambió el retorno de vinculación';
  end if;
  v_src:=replace(v_src,v_ancla,E'  perform private.materializar_capital_valoraciones_para(1,\n'
    ||E'    case when p_contrato is not null then ''contrato'' else ''cierre_externo'' end,coalesce(p_contrato,p_cierre));\n'||v_ancla);
  execute format('create or replace function private.inversion_vincular_fuente(p_persona uuid,p_contrato uuid,p_cierre uuid,p_por uuid,p_inicial boolean default false)
    returns uuid language plpgsql security definer set search_path='''' as %L',v_src);
end $vincular$;

-- El alta CRM también conserva esta garantía si la identidad unificada está
-- suspendida. Una vinculación previa en la misma transacción es idempotente.
do $alta$
declare v_src text; v_ancla text:='  return v_resultado || jsonb_build_object(''cuenta_bancaria_id'', v_cuenta_id);';
begin
  select prosrc into strict v_src from pg_proc where oid='crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)'::regprocedure;
  if (length(v_src)-length(replace(v_src,v_ancla,'')))/length(v_ancla)<>1 then
    raise exception 'Cambió el retorno del alta contractual CRM';
  end if;
  v_src:=replace(v_src,v_ancla,E'  perform private.materializar_capital_valoraciones_para(1,''contrato'',v_contrato_id);\n'||v_ancla);
  execute format('create or replace function crm.crear_contrato_con_cuenta(p_contrato jsonb,p_cronograma jsonb,p_cuenta jsonb)
    returns jsonb language plpgsql security definer set search_path='''' as %L',v_src);
end $alta$;

-- Mismo orden que cerrar_periodo: cerrojo global antes de la fila fuente.
-- Mantiene autorización, validaciones, locks mensuales y auditoría originales.
do $corregir$
declare v_src text; v_lectura text:='  select c.* into v_contrato';
  v_retorno text:=E'  return jsonb_build_object(\n    ''ok'', true,\n    ''cambio'', true,';
begin
  select prosrc into strict v_src from pg_proc where oid='crm.corregir_fecha_cierre_comercial(uuid,date,text)'::regprocedure;
  if (length(v_src)-length(replace(v_src,v_lectura,'')))/length(v_lectura)<>1
    or (length(v_src)-length(replace(v_src,v_retorno,'')))/length(v_retorno)<>1 then
    raise exception 'Cambió el corrector de fecha comercial';
  end if;
  v_src:=replace(v_src,v_lectura,E'  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(''crm.periodos_cerrados'')::bigint);\n\n'||v_lectura);
  v_src:=replace(v_src,v_retorno,E'  perform private.materializar_capital_valoraciones_para(1,''contrato'',p_contrato_id);\n\n'||v_retorno);
  execute format('create or replace function crm.corregir_fecha_cierre_comercial(p_contrato_id uuid,p_fecha date,p_motivo text)
    returns jsonb language plpgsql security definer set search_path='''' as %L',v_src);
end $corregir$;

create function private.capital_valorar_cierre_trg()
returns trigger language plpgsql security definer set search_path='' as $$ begin
  perform private.materializar_capital_valoraciones_para(1,'cierre_externo',new.id);
  return new;
end $$;
alter function private.capital_valorar_cierre_trg() owner to postgres;
revoke all on function private.capital_valorar_cierre_trg() from public,anon,authenticated,service_role;
create trigger zz_capital_valorar_cierre after insert or update of monto,moneda,fecha_comercial,fecha_imputacion
  on crm.cierres_externos for each row execute function private.capital_valorar_cierre_trg();

comment on function private.materializar_capital_valoraciones_para(integer,text,uuid) is
  'Algoritmo monetario compartido: lote con identidad NULL o una sola fuente al escribir. Sin HTTP ni publicación parcial de cortes.';
commit;
