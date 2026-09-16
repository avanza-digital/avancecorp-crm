-- Reversa deliberada: restaura el comportamiento anterior, incluida la carrera F3.
-- No activa ni apaga el piloto. No ejecutar automáticamente.
begin;
set local lock_timeout='5s';
do $preflight$
begin
  if (select md5(prosrc) from pg_proc where oid=to_regprocedure('private.trg_piloto_f8_control_validar()'))
      is distinct from '201a4b2fd6d062d7930e673d9986f5de' then
    raise exception 'El control F8 no coincide con la corrección a revertir';
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
begin
  perform pg_advisory_xact_lock(hashtext('crm_piloto_f8_control'));
  if tg_op = 'DELETE' then
    raise exception 'El control F8 es permanente; solo se apaga' using errcode='55000';
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
    if not coalesce((select activo from crm.multiempresa_flags
        where nombre='resolver_en_puertas'),false)
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
  if (select md5(prosrc) from pg_proc where oid='private.trg_piloto_f8_control_validar()'::regprocedure)
      is distinct from 'dca0a332f21fda89f88f4614e0db0c75' then
    raise exception 'La reversa no restauró la función esperada';
  end if;
end;
$postflight$;
commit;
