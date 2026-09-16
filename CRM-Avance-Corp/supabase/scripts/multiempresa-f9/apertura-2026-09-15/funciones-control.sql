-- Fuente consultada en producción READ ONLY: 2026-09-16T00:30:09.973047+00:00
-- Solo evidencia; NO ejecutar ni instalar.
CREATE OR REPLACE FUNCTION crm.cartera_inversionistas_estado_fn()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  v_uid uuid:=(select auth.uid());
  v_rol text:=private.rol_crm(v_uid);
  v_lector boolean:=private.es_lector_global();
  v_f3 boolean;
  v_f5 boolean;
  v_piloto boolean;
  v_cobertura boolean;
  v_escritura boolean;
begin
  if v_uid is null or not coalesce(
      v_rol in ('vendedor','supervisor','gerencia') or v_lector,false) then
    raise exception 'No autorizado' using errcode='42501';
  end if;
  v_f3:=private.resolver_en_puertas_bajo_candado();
  select private.rol_crm(v_uid),private.es_lector_global() into v_rol,v_lector;
  if not coalesce(v_rol in ('vendedor','supervisor','gerencia') or v_lector,false) then
    raise exception 'No autorizado' using errcode='42501';
  end if;
  perform pg_advisory_xact_lock_shared(hashtext('crm_flag_ficha_360_neutral'));
  select coalesce(bool_or(activo),false) into v_f5
    from crm.multiempresa_flags where nombre='ficha_360_neutral';
  v_escritura:=private.inversiones_escritura_bajo_candado();
  v_piloto:=private.piloto_f8_actor_activo(v_uid);
  if not v_f3 or not (v_f5 or v_piloto) then
    return jsonb_build_object('version',1,'habilitada',false,
      'escritura_habilitada',false,
      'motivo','La cartera multiempresa aún no está habilitada');
  end if;
  select not exists (
    select 1 from private.cartera_f5_fuentes_reales() f
    left join crm.inversionistas i on i.id=f.inversionista_id
    where not coalesce(f.identidad_coherente,false) or i.id is null
      or i.inversionista_canonico_id is not null
  ) into v_cobertura;
  return jsonb_build_object('version',1,'habilitada',v_cobertura,
    'escritura_habilitada',v_cobertura and not v_lector
      and private.puede_gestionar_contratos_crm() and v_escritura,
    'motivo',case when not v_cobertura
      then 'La cartera requiere conciliación antes de habilitarse' end);
end;
$function$

CREATE OR REPLACE FUNCTION crm.postventa_estado_fn()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$begin

declare v_rol text; v_on boolean;
begin
  v_rol:=private.rol_crm(auth.uid());
  if auth.uid() is null or not private.puede_acceder_crm() then
    raise exception 'No autorizado' using errcode='42501';
  end if;
  v_on:=private.postventa_modo();
  v_rol:=private.rol_crm(auth.uid());
  v_on:=v_on and coalesce(v_rol in ('vendedor','supervisor','gerencia'),false)
    and not private.es_lector_global();
  if v_on then v_on:=(crm.cartera_inversionistas_estado_fn()->>'habilitada')::boolean; end if;
  return jsonb_build_object('version',1,'habilitada',v_on);
end;

exception when serialization_failure then
  raise exception using errcode='PT409', message='La operación coincidió con otro cambio. Vuelve a intentarlo.';
end;
$function$

CREATE OR REPLACE FUNCTION private.piloto_f8_actor_activo(p_actor uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
begin
  if p_actor is null or not private.piloto_f8_modo_activo() then return false; end if;
  return exists (
    select 1 from crm.piloto_f8_miembros m
    where m.perfil_id=p_actor and m.activo
  );
end;
$function$

CREATE OR REPLACE FUNCTION private.piloto_f8_control_activo()
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare v_control crm.piloto_f8_control%rowtype;
begin
  perform pg_advisory_xact_lock_shared(hashtext('crm_piloto_f8_control'));
  select * into v_control from crm.piloto_f8_control where singleton;
  if not found or not v_control.activo
    or v_control.inicia_en > statement_timestamp()
    or v_control.vence_en <= statement_timestamp() then
    return false;
  end if;
  return true;
end;
$function$

CREATE OR REPLACE FUNCTION private.piloto_f8_modo_activo()
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare v_control crm.piloto_f8_control%rowtype;
begin
  if not private.piloto_f8_control_activo() then return false; end if;
  select * into strict v_control from crm.piloto_f8_control where singleton;
  return coalesce((select count(*)=4
      and count(*) filter(where m.rol_esperado='gerencia')=1
      and count(*) filter(where m.rol_esperado='supervisor')=1
      and count(*) filter(where m.rol_esperado='vendedor')=2
      and count(*) filter(where m.habilitado_desde <= v_control.inicia_en
        and m.vence_en > statement_timestamp() and m.vence_en <= v_control.vence_en
        and m.actualizado_por is not null and p.activo and e.activo
        and e.rol_crm=m.rol_esperado)=4
    from crm.piloto_f8_miembros m
    join public.perfiles p on p.id=m.perfil_id
    join crm.equipo e on e.perfil_id=m.perfil_id
    where m.activo),false);
end;
$function$

CREATE OR REPLACE FUNCTION private.trg_multiempresa_flags_bloquear_piloto_f8()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_encendido boolean;
begin
  if tg_op='INSERT' then
    v_encendido:=new.activo;
  else
    v_encendido:=new.activo and not old.activo;
  end if;
  if new.nombre in ('inversiones_escritura','ficha_360_neutral',
      'postventa_neutral','metricas_multiempresa_sombra') and v_encendido then
    if current_setting('transaction_isolation') <> 'read committed' then
      raise exception 'El rollout multiempresa requiere READ COMMITTED (aislamiento actual: %)',
        current_setting('transaction_isolation') using errcode='0A000';
    end if;
    perform pg_advisory_xact_lock(hashtext('crm_piloto_f8_control'));
    if exists(select 1 from crm.piloto_f8_control where singleton and activo) then
      raise exception 'Apaga F8 antes de activar el rollout global'
        using errcode='P0409';
    end if;
  end if;
  return new;
end;
$function$

CREATE OR REPLACE FUNCTION private.trg_multiempresa_flags_serializa_puertas()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  -- F2.b [D-5] (Codex v3 #3/#4): encender o apagar una bandera espera a que terminen las puertas que la leyeron bajo el
  -- candado compartido (pg_advisory_xact_lock_shared('crm_flag_<nombre>')) y bloquea a las que lleguen hasta que el cambio
  -- se confirme. Así ninguna llamada termina con una bandera distinta de la que leyó. Candado por bandera, transaccional.
  if new.activo is distinct from old.activo then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm_flag_' || new.nombre));
  end if;
  return new;
end;
$function$

CREATE OR REPLACE FUNCTION private.trg_piloto_f8_control_validar()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$

CREATE OR REPLACE FUNCTION private.trg_piloto_f8_miembros_controlar()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_activo boolean;
begin
  perform pg_advisory_xact_lock(hashtext('crm_piloto_f8_control'));
  if tg_op = 'DELETE' then
    raise exception 'La membresía F8 se desactiva; no se borra' using errcode='55000';
  end if;
  select activo into v_activo from crm.piloto_f8_control where singleton;
  if v_activo then
    if tg_op = 'INSERT' then
      raise exception 'Apaga F8 antes de ampliar o cambiar el equipo piloto'
        using errcode='P0409';
    end if;
    if new.activo
      or new.perfil_id is distinct from old.perfil_id
      or new.rol_esperado is distinct from old.rol_esperado
      or new.habilitado_desde is distinct from old.habilitado_desde
      or new.vence_en is distinct from old.vence_en then
      raise exception 'Apaga F8 antes de ampliar o cambiar el equipo piloto'
        using errcode='P0409';
    end if;
    update crm.piloto_f8_control
    set activo=false,motivo='Suspensión automática por revocación de integrante F8'
    where singleton;
  end if;
  new.actualizado_en := statement_timestamp();
  new.actualizado_por := coalesce(auth.uid(),new.actualizado_por);
  return new;
end;
$function$
