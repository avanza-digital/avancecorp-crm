-- Corrección de D-19 descubierta al ejecutar la matriz RLS completa.
-- La activación F8 valida F3 bajo candado y rechaza conflictos sin esperar.
-- No activa el piloto, cambia banderas ni escribe datos de negocio.
-- F3 conserva su función de apagado general: las puertas F4/F5/F6 lo revisan.
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
do $preflight$
begin
  if (select md5(pg_get_functiondef(oid)) from pg_proc where oid=to_regprocedure('private.trg_piloto_f8_control_validar()'))
     is distinct from '47585a27b991a442bb09b3477be5f224' then
    raise exception 'El control F8 cambió; revisar la definición antes de instalar';
  end if;
  if not exists(select 1 from pg_trigger
      where tgrelid='crm.piloto_f8_control'::regclass
        and tgname='trg_piloto_f8_control_00_validar' and tgtype=27 and tgenabled='O'
        and tgfoid='private.trg_piloto_f8_control_validar()'::regprocedure) then
    raise exception 'El trigger F8 no coincide: exige BEFORE DELETE OR UPDATE habilitado';
  end if;
end;
$preflight$;

CREATE OR REPLACE FUNCTION "private"."trg_piloto_f8_control_validar"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_total integer;
  v_validos integer;
  v_gerencia integer;
  v_supervisor integer;
  v_vendedores integer;
  v_huecos integer;
  v_f3 boolean := false;
begin
  if tg_op = 'DELETE' then
    raise exception 'El control F8 es permanente; solo se apaga' using errcode='55000';
  end if;
  if tg_op = 'UPDATE' then
    if new.activo then
      if current_setting('transaction_isolation') <> 'read committed' then
        raise exception 'F8 requiere READ COMMITTED (aislamiento actual: %)',
          current_setting('transaction_isolation') using errcode='0A000';
      end if;
      -- BEFORE ROW ya retiene la fila F8. No esperar otros candados aquí:
      -- una transacción que cambia F3 y luego F8 podría esperar esa misma fila.
      -- El rechazo P0409 revierte la sentencia; el operador puede reintentar.
      if not pg_catalog.pg_try_advisory_xact_lock_shared(pg_catalog.hashtext('crm_flag_resolver_en_puertas')) then
        raise exception 'F3 está cambiando; reintenta la activación F8' using errcode='P0409';
      end if;
      v_f3:=private.resolver_en_puertas_bajo_candado();
      if not pg_catalog.pg_try_advisory_xact_lock(pg_catalog.hashtext('crm_piloto_f8_control')) then
        raise exception 'El control F8 está ocupado; reintenta la activación' using errcode='P0409';
      end if;
    else
      -- Apagar no consulta F3 ni exige READ COMMITTED.
      perform pg_advisory_xact_lock(hashtext('crm_piloto_f8_control'));
    end if;
  end if;
  if new.singleton is distinct from true then
    raise exception 'El control F8 debe conservar su fila única' using errcode='23514';
  end if;

  new.actualizado_en := statement_timestamp();
  new.actualizado_por := coalesce(auth.uid(),new.actualizado_por);

  if new.activo then
    if current_setting('transaction_isolation') <> 'read committed' then
      raise exception 'F8 requiere READ COMMITTED (aislamiento actual: %)',
        current_setting('transaction_isolation') using errcode='0A000';
    end if;
    if new.inicia_en is null or new.vence_en is null
      or new.inicia_en > statement_timestamp()
      or new.vence_en <= statement_timestamp()
      or new.vence_en-new.inicia_en > interval '30 days' then
      raise exception 'La ventana F8 debe estar vigente y no superar 30 días'
        using errcode='22023';
    end if;
    if old.activo and (new.inicia_en is distinct from old.inicia_en
        or new.vence_en > old.vence_en) then
      raise exception 'La ventana F8 activa solo puede acortarse; apaga para ampliarla'
        using errcode='P0409';
    end if;
    if new.motivo is null or length(btrim(new.motivo)) < 8 then
      raise exception 'Falta el motivo del piloto F8' using errcode='22023';
    end if;
    if v_f3 is not true
      or exists(select 1 from crm.multiempresa_flags
        where nombre in ('inversiones_escritura','ficha_360_neutral',
          'postventa_neutral','metricas_multiempresa_sombra') and activo) then
      raise exception 'El piloto F8 requiere F3 ON y F4/F5/F6/F7 globales OFF'
        using errcode='P0409';
    end if;

    if new.actualizado_por is null then
      raise exception 'F8 requiere responsable explícito de activación'
        using errcode='22023';
    end if;

    select count(*),
      count(*) filter(where m.habilitado_desde <= new.inicia_en
        and m.vence_en > statement_timestamp() and m.vence_en <= new.vence_en
        and m.actualizado_por is not null and exists (
        select 1 from public.perfiles p join crm.equipo e on e.perfil_id=p.id
        where p.id=m.perfil_id and p.activo and e.activo
          and e.rol_crm=m.rol_esperado)),
      count(*) filter(where rol_esperado='gerencia'),
      count(*) filter(where rol_esperado='supervisor'),
      count(*) filter(where rol_esperado='vendedor')
    into v_total,v_validos,v_gerencia,v_supervisor,v_vendedores
    from crm.piloto_f8_miembros m
    where m.activo;

    if v_total<>4 or v_validos<>4 or v_gerencia<>1
      or v_supervisor<>1 or v_vendedores<>2 then
      raise exception 'F8 exige exactamente Gerencia, un supervisor y dos vendedores vigentes'
        using errcode='P0409';
    end if;

    select count(*) into v_huecos
    from private.cartera_f5_fuentes_reales() f
    left join crm.inversionistas i on i.id=f.inversionista_id
    where not coalesce(f.identidad_coherente,false) or i.id is null
      or i.inversionista_canonico_id is not null;
    if v_huecos<>0 then
      raise exception 'F8 requiere resolver % fuentes sin identidad coherente',v_huecos
        using errcode='P0409';
    end if;
  end if;

  new.revision := old.revision + 1;
  return new;
end;
$$;

do $postflight$
begin
  if not exists(select 1 from pg_proc where oid='private.trg_piloto_f8_control_validar()'::regprocedure
      and md5(prosrc)='201a4b2fd6d062d7930e673d9986f5de' and prosecdef
      and proowner='postgres'::regrole and proconfig = array['search_path=""']
      and provolatile='v' and proparallel='u' and procost=100 and prorows=0
      and not proisstrict and not proleakproof) then
    raise exception 'El control F8 no conservó su definición y perímetro';
  end if;
  if exists(select 1 from unnest(array['anon','authenticated','service_role']) r(rol)
      where has_function_privilege(r.rol,'private.trg_piloto_f8_control_validar()','EXECUTE'))
    or exists(select 1 from pg_proc p,aclexplode(p.proacl) a
      where p.oid='private.trg_piloto_f8_control_validar()'::regprocedure and a.grantee=0) then
    raise exception 'El control F8 no debe estar expuesto a la API';
  end if;
  if not exists(select 1 from pg_trigger
      where tgrelid='crm.piloto_f8_control'::regclass
        and tgname='trg_piloto_f8_control_00_validar' and tgtype=27 and tgenabled='O'
        and tgfoid='private.trg_piloto_f8_control_validar()'::regprocedure) then
    raise exception 'El trigger F8 no coincide: exige BEFORE DELETE OR UPDATE habilitado';
  end if;
end;
$postflight$;
commit;
