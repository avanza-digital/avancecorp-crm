-- F8: control de piloto económico por actor, instalado siempre APAGADO.
-- No enlaza identidades, no crea inversiones, no activa F4/F5/F6/F7 y no toca
-- las fuentes económicas. El piloto se configura y activa después, por SQL
-- administrativo explícitamente aprobado.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $preflight$
declare r record;
begin
  if to_regclass('crm.piloto_f8_control') is not null
    or to_regclass('crm.piloto_f8_miembros') is not null then
    raise exception 'F8 ya existe; no se reinstala';
  end if;

  for r in select * from (values
    ('private.inversiones_escritura_bajo_candado()','cf559da325be6be049a70d67d6212d81','{postgres=X/postgres}'),
    ('private.inversion_persona_autorizada(uuid)','758d7a5b9f6e3aaacfa0b240d8e1d3c9','{postgres=X/postgres}'),
    ('crm.cartera_inversionistas_estado_fn()','ec7e3d8d67a0ee52d176bcbd03b4cc5c','{postgres=X/postgres,authenticated=X/postgres}'),
    ('private.postventa_modo()','c110199948db88483875ee376cb28bfa','{postgres=X/postgres}'),
    ('private.postventa_visible_actor(uuid,uuid)','16dcf91c2217edc7f2c2d10dd3543597','{postgres=X/postgres}')
  ) as esperado(firma,huella,acl) loop
    if to_regprocedure(r.firma) is null
      or md5(pg_get_functiondef(to_regprocedure(r.firma))) is distinct from r.huella
      or (select p.proacl::text from pg_proc p
          where p.oid=to_regprocedure(r.firma)) is distinct from r.acl then
      raise exception 'La base cambió: revisar % antes de instalar F8', r.firma;
    end if;
  end loop;

  if not coalesce((select activo from crm.multiempresa_flags
      where nombre = 'resolver_en_puertas'), false)
    or exists (select 1 from crm.multiempresa_flags
      where nombre in ('inversiones_escritura','ficha_360_neutral',
        'postventa_neutral','metricas_multiempresa_sombra') and activo) then
    raise exception 'F8 se instala con F3 ON y F4/F5/F6/F7 OFF';
  end if;
end;
$preflight$;

create table crm.piloto_f8_control (
  singleton boolean primary key default true check (singleton),
  activo boolean not null default false,
  revision bigint not null default 0 check (revision >= 0),
  inicia_en timestamptz,
  vence_en timestamptz,
  motivo text check (motivo is null or length(btrim(motivo)) between 8 and 500),
  actualizado_en timestamptz not null default statement_timestamp()
    check (isfinite(actualizado_en)),
  actualizado_por uuid references public.perfiles(id),
  check ((inicia_en is null and vence_en is null)
    or (inicia_en is not null and vence_en is not null and inicia_en < vence_en))
);
comment on table crm.piloto_f8_control is
  'F8: interruptor administrativo único del piloto económico. Nace OFF; sin permisos Data API. El apagado detiene capacidades nuevas y conserva todos los hechos.';

create table crm.piloto_f8_miembros (
  perfil_id uuid primary key references public.perfiles(id),
  rol_esperado text not null check (rol_esperado in ('gerencia','supervisor','vendedor')),
  activo boolean not null default true,
  habilitado_desde timestamptz not null default statement_timestamp()
    check (isfinite(habilitado_desde)),
  vence_en timestamptz not null check (isfinite(vence_en)),
  motivo text not null check (length(btrim(motivo)) between 8 and 500),
  actualizado_en timestamptz not null default statement_timestamp()
    check (isfinite(actualizado_en)),
  actualizado_por uuid references public.perfiles(id),
  check (habilitado_desde < vence_en
    and vence_en-habilitado_desde <= interval '30 days')
);
comment on table crm.piloto_f8_miembros is
  'F8: cuatro participantes nominales y temporales del piloto (Gerencia, un supervisor y dos vendedores). La membresía CRM vigente se revalida en cada llamada.';

alter table crm.piloto_f8_control enable row level security;
alter table crm.piloto_f8_miembros enable row level security;
revoke all on crm.piloto_f8_control, crm.piloto_f8_miembros
  from public, anon, authenticated, service_role;

insert into crm.piloto_f8_control(singleton,activo,revision)
values (true,false,0);

create trigger trg_audit_piloto_f8_control
  after insert or update or delete on crm.piloto_f8_control
  for each row execute function private.log_audit_crm();
create trigger trg_audit_piloto_f8_miembros
  after insert or update or delete on crm.piloto_f8_miembros
  for each row execute function private.log_audit_crm();

create function private.trg_piloto_f8_miembros_controlar()
returns trigger language plpgsql security definer set search_path='' as $f$
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
$f$;
revoke all on function private.trg_piloto_f8_miembros_controlar()
  from public, anon, authenticated, service_role;

create trigger trg_piloto_f8_miembros_00_controlar
  before insert or update or delete on crm.piloto_f8_miembros
  for each row execute function private.trg_piloto_f8_miembros_controlar();

create function private.trg_piloto_f8_control_validar()
returns trigger language plpgsql security definer set search_path='' as $f$
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
    from private.cartera_f5_fuentes() f
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
$f$;
revoke all on function private.trg_piloto_f8_control_validar()
  from public, anon, authenticated, service_role;

create trigger trg_piloto_f8_control_00_validar
  before update or delete on crm.piloto_f8_control
  for each row execute function private.trg_piloto_f8_control_validar();

-- F8 y el rollout global son modos mutuamente excluyentes. La misma llave
-- serializa el encendido de ambos lados para que dos administradores no puedan
-- abrir el piloto y una bandera global en carreras concurrentes.
create function private.trg_multiempresa_flags_bloquear_piloto_f8()
returns trigger language plpgsql security definer set search_path='' as $f$
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
$f$;
revoke all on function private.trg_multiempresa_flags_bloquear_piloto_f8()
  from public, anon, authenticated, service_role;

create trigger trg_multiempresa_flags_01_bloquear_piloto_f8
  before insert or update on crm.multiempresa_flags
  for each row execute function private.trg_multiempresa_flags_bloquear_piloto_f8();

create function private.piloto_f8_control_activo()
returns boolean language plpgsql volatile security definer
set search_path='' set lock_timeout='5s' as $f$
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
$f$;
revoke all on function private.piloto_f8_control_activo()
  from public, anon, authenticated, service_role;

create function private.piloto_f8_modo_activo()
returns boolean language plpgsql volatile security definer
set search_path='' set lock_timeout='5s' as $f$
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
$f$;
revoke all on function private.piloto_f8_modo_activo()
  from public, anon, authenticated, service_role;

create function private.piloto_f8_actor_activo(p_actor uuid)
returns boolean language plpgsql volatile security definer
set search_path='' set lock_timeout='5s' as $f$
begin
  if p_actor is null or not private.piloto_f8_modo_activo() then return false; end if;
  return exists (
    select 1 from crm.piloto_f8_miembros m
    where m.perfil_id=p_actor and m.activo
  );
end;
$f$;
revoke all on function private.piloto_f8_actor_activo(uuid)
  from public, anon, authenticated, service_role;

-- F4: durante un piloto sano, los observadores relacionales acompañan también
-- las altas legadas de usuarios ajenos. La capacidad interactiva nueva se
-- restringe por actor en inversion_persona_autorizada; así no nace una cartera
-- parcial ni se abre el flujo F4 al resto del equipo.
create or replace function private.inversiones_escritura_bajo_candado()
returns boolean language plpgsql volatile security definer set search_path='' as $f$
begin
  if not private.resolver_en_puertas_bajo_candado() then return false; end if;
  perform pg_advisory_xact_lock_shared(hashtext('crm_flag_inversiones_escritura'));
  if coalesce((select activo from crm.multiempresa_flags
      where nombre='inversiones_escritura'),false) then
    return true;
  end if;
  return private.piloto_f8_control_activo();
end;
$f$;
revoke all on function private.inversiones_escritura_bajo_candado()
  from public, anon, authenticated, service_role;

create or replace function private.inversion_persona_autorizada(p_persona uuid)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='5s' as $f$
declare
  v_uid uuid := (select auth.uid());
  v_rol text;
  v_i crm.inversionistas%rowtype;
  v_docs text[];
  v_docs_actuales text[];
  v_persona uuid;
  v_global boolean;
begin
  if v_uid is null or not private.puede_gestionar_contratos_crm() then
    raise exception 'No autorizado para registrar inversiones' using errcode='42501';
  end if;
  if not private.inversiones_escritura_bajo_candado() then
    raise exception 'El registro multiempresa todavía no está habilitado' using errcode='P0409';
  end if;
  select coalesce(activo,false) into v_global from crm.multiempresa_flags
  where nombre='inversiones_escritura';
  if not v_global then
    if not private.piloto_f8_actor_activo(v_uid) then
      raise exception 'El registro multiempresa está limitado al equipo piloto'
        using errcode='42501';
    end if;
    perform private.cartera_f5_exigir();
  end if;
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia',0));
  v_rol := private.rol_crm(v_uid);
  if v_rol is null or v_rol not in ('vendedor','supervisor','gerencia') then
    raise exception 'No autorizado para registrar inversiones' using errcode='42501';
  end if;
  v_persona := private.inversionista_canonica(p_persona);
  v_docs := private.identidad_bloquear_documentos_de(array[v_persona]);
  select * into v_i from crm.inversionistas where id=v_persona for update;
  if not found or not coalesce((
    v_rol='gerencia' or v_i.responsable_relacion_id in (select private.vendedor_ids_visibles(v_uid))
  ),false) then
    raise exception 'Persona no encontrada o fuera de tu ámbito' using errcode='42501';
  end if;
  if private.inversionista_canonica(p_persona) is distinct from v_persona then
    raise exception 'La identidad cambió mientras se esperaba; vuelve a cargar la persona' using errcode='40001';
  end if;
  select coalesce(array_agg(k order by k),'{}') into v_docs_actuales
  from (select distinct tipo_documento||':'||documento_normalizado as k
        from crm.inversionista_identificadores where inversionista_id=v_persona and estado='vigente') d;
  if v_docs is distinct from v_docs_actuales then
    raise exception 'El documento cambió durante la operación; vuelve a cargar la persona' using errcode='40001';
  end if;
  return jsonb_build_object('inversionista_id',v_i.id,'perfil_id',v_i.perfil_id,
    'responsable_id',v_i.responsable_relacion_id);
end;
$f$;
revoke all on function private.inversion_persona_autorizada(uuid)
  from public, anon, authenticated, service_role;

-- F5: la cobertura completa sigue siendo obligatoria. F8 no convierte una
-- cartera parcial en una suma aparentemente completa.
create or replace function crm.cartera_inversionistas_estado_fn()
returns jsonb language plpgsql volatile security definer
set search_path='' set lock_timeout='5s' as $f$
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
    select 1 from private.cartera_f5_fuentes() f
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
$f$;
revoke all on function crm.cartera_inversionistas_estado_fn()
  from public, anon, authenticated, service_role;
grant execute on function crm.cartera_inversionistas_estado_fn() to authenticated;

-- F6: las banderas globales continúan gobernando el rollout general. El actor
-- nominal del piloto obtiene la misma capacidad sin abrirla al resto del equipo.
create or replace function private.postventa_modo()
returns boolean language plpgsql volatile security definer
set search_path='' set lock_timeout='5s' as $f$
declare v_f3 boolean; v_flag record; v_total integer:=0; v_global boolean:=true;
begin
  v_f3:=private.resolver_en_puertas_bajo_candado();
  for v_flag in select nombre,activo from crm.multiempresa_flags
    where nombre in ('ficha_360_neutral','postventa_neutral')
    order by nombre for share nowait
  loop v_total:=v_total+1; v_global:=v_global and v_flag.activo; end loop;
  if not v_f3 or v_total<>2 then return false; end if;
  return v_global or private.piloto_f8_actor_activo(auth.uid());
exception when lock_not_available then
  raise exception 'Está cambiando la disponibilidad de postventa; vuelve a intentar'
    using errcode='40001';
end;
$f$;
revoke all on function private.postventa_modo()
  from public, anon, authenticated, service_role;

create or replace function private.postventa_visible_actor(p_persona uuid,p_actor uuid)
returns boolean language plpgsql volatile security definer
set search_path='' set lock_timeout='5s' as $f$
declare v_global boolean; v_piloto boolean;
begin
  if not private.resolver_en_puertas_bajo_candado() then return false; end if;
  select count(*)=2 and bool_and(activo) into v_global
  from crm.multiempresa_flags
  where nombre in ('ficha_360_neutral','postventa_neutral');
  v_piloto:=private.piloto_f8_actor_activo(p_actor);
  if not coalesce(v_global,false) and not v_piloto then return false; end if;
  return (select coalesce(
    private.rol_crm(p_actor) in ('vendedor','supervisor','gerencia')
    and exists(select 1 from crm.inversionistas i
      where i.id=private.inversionista_canonica(p_persona)
        and (private.rol_crm(p_actor)='gerencia'
          or i.responsable_relacion_id=p_actor
          or i.responsable_relacion_id in
            (select private.vendedor_ids_visibles(p_actor)))),false));
end;
$f$;
revoke all on function private.postventa_visible_actor(uuid,uuid)
  from public, anon, authenticated, service_role;

do $postflight$
declare
  v_oid regprocedure;
  v_f5 regprocedure:='crm.cartera_inversionistas_estado_fn()'::regprocedure;
  v_triggers integer;
begin
  if (select count(*) from crm.piloto_f8_control)<>1
    or (select activo from crm.piloto_f8_control where singleton)
    or exists(select 1 from crm.piloto_f8_miembros)
    or exists(select 1 from crm.multiempresa_flags
      where nombre in ('inversiones_escritura','ficha_360_neutral',
        'postventa_neutral','metricas_multiempresa_sombra') and activo) then
    raise exception 'F8 debe quedar instalado OFF, vacío y sin activar F4-F7';
  end if;
  if not (select activo from crm.multiempresa_flags where nombre='resolver_en_puertas') then
    raise exception 'F3 debe permanecer encendida';
  end if;
  if not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
      where n.nspname='crm' and c.relname in ('piloto_f8_control','piloto_f8_miembros')
        and c.relrowsecurity group by n.nspname having count(*)=2) then
    raise exception 'Las tablas F8 deben conservar RLS';
  end if;
  if exists(select 1 from pg_class c,
      lateral aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a
      where c.oid=any(array['crm.piloto_f8_control'::regclass,
        'crm.piloto_f8_miembros'::regclass])
        and a.grantee=any(array[0::oid,'anon'::regrole::oid,
          'authenticated'::regrole::oid,'service_role'::regrole::oid]))
    or exists(select 1 from pg_attribute a,
      lateral aclexplode(a.attacl) x
      where a.attrelid=any(array['crm.piloto_f8_control'::regclass,
        'crm.piloto_f8_miembros'::regclass]) and a.attnum>0
        and x.grantee=any(array[0::oid,'anon'::regrole::oid,
          'authenticated'::regrole::oid,'service_role'::regrole::oid])) then
    raise exception 'El control F8 quedó expuesto a la Data API';
  end if;
  select count(*) into v_triggers from pg_trigger
  where not tgisinternal and tgenabled='O' and tgname=any(array[
    'trg_audit_piloto_f8_control','trg_audit_piloto_f8_miembros',
    'trg_piloto_f8_miembros_00_controlar','trg_piloto_f8_control_00_validar',
    'trg_multiempresa_flags_01_bloquear_piloto_f8']);
  if v_triggers<>5 then
    raise exception 'F8 requiere sus cinco triggers activos';
  end if;
  foreach v_oid in array array[
    'private.trg_piloto_f8_miembros_controlar()'::regprocedure,
    'private.trg_piloto_f8_control_validar()'::regprocedure,
    'private.trg_multiempresa_flags_bloquear_piloto_f8()'::regprocedure,
    'private.piloto_f8_control_activo()'::regprocedure,
    'private.piloto_f8_modo_activo()'::regprocedure,
    'private.piloto_f8_actor_activo(uuid)'::regprocedure,
    'private.inversiones_escritura_bajo_candado()'::regprocedure,
    'private.inversion_persona_autorizada(uuid)'::regprocedure,
    'crm.cartera_inversionistas_estado_fn()'::regprocedure,
    'private.postventa_modo()'::regprocedure,
    'private.postventa_visible_actor(uuid,uuid)'::regprocedure
  ] loop
    if not exists(select 1 from pg_proc p where p.oid=v_oid
        and p.prosecdef and p.proowner='postgres'::regrole
        and p.proconfig @> array['search_path=""'])
      or exists(select 1 from pg_proc p,
        lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
        where p.oid=v_oid
          and a.grantee=any(array[0::oid,'anon'::regrole::oid,
            'authenticated'::regrole::oid,'service_role'::regrole::oid])
          and not (p.oid=v_f5 and a.grantee='authenticated'::regrole::oid
            and a.privilege_type='EXECUTE')) then
      raise exception 'Función F8 sin endurecimiento: %',v_oid;
    end if;
  end loop;
  if has_function_privilege('anon','crm.cartera_inversionistas_estado_fn()','EXECUTE')
    or has_function_privilege('service_role','crm.cartera_inversionistas_estado_fn()','EXECUTE')
    or not has_function_privilege('authenticated','crm.cartera_inversionistas_estado_fn()','EXECUTE') then
    raise exception 'F8 alteró los permisos públicos de la capacidad F5';
  end if;
end;
$postflight$;

notify pgrst, 'reload schema';
commit;
