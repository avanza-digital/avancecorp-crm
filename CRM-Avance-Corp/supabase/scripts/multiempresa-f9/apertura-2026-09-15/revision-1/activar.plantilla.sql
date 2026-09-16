-- Apertura general autorizada por Miguel: «OK ACTIVALO PRO FAVOR».
-- Ejecución administrativa, sin simular firmas financieras ni sesiones humanas.
begin isolation level read committed;
set local search_path='';
set local lock_timeout='3s';
set local statement_timeout='30s';
do $f9$
declare
  cfg constant jsonb:='__CONFIG__'::jsonb;
  banderas jsonb;equipo jsonb;miembros jsonb;control jsonb;v_fn record;cantidad integer;triggers jsonb;
  antes text;despues text;v_revision integer;
  actor record;f5 jsonb;f6 jsonb;error_f5 text;roles jsonb:='[]';
begin
  if current_user<>'postgres' or auth.uid() is not null then
    raise exception 'Se requiere administración sin suplantación' using errcode='P0409';end if;
  if statement_timestamp()>(cfg->>'vence_sql')::timestamptz then
    raise exception 'Preflight de apertura vencido; revisar otra vez' using errcode='P0409';end if;
  -- Mismo orden que los lectores/escritores: F3 exterior, después F5/F4/F6/F8.
  perform pg_advisory_xact_lock(hashtext('crm_flag_resolver_en_puertas'));
  perform pg_advisory_xact_lock(hashtext('crm_flag_ficha_360_neutral'));
  perform pg_advisory_xact_lock(hashtext('crm_flag_inversiones_escritura'));
  perform pg_advisory_xact_lock(hashtext('crm_flag_postventa_neutral'));
  perform pg_advisory_xact_lock(hashtext('crm_piloto_f8_control'));
  select jsonb_object_agg(nombre,activo) into banderas from crm.multiempresa_flags;
  if banderas is distinct from '{"resolver_en_puertas":true,"inversiones_escritura":false,"ficha_360_neutral":false,"postventa_neutral":false,"metricas_multiempresa_sombra":false}'::jsonb then
    raise exception 'Configuración cambió; no abrir' using errcode='P0409';end if;
  select to_jsonb(c)-'actualizado_en' into strict control from crm.piloto_f8_control c where singleton;
  select jsonb_agg(to_jsonb(m)-'actualizado_en' order by perfil_id) into miembros from crm.piloto_f8_miembros m where activo;
  if control is distinct from cfg->'control' or miembros is distinct from cfg->'miembros'
    or not private.piloto_f8_modo_activo() then
    raise exception 'Cambió el piloto, la revisión o su vigencia' using errcode='P0409';end if;
  select jsonb_agg(jsonb_build_object('perfil_id',p.id,'rol_portal',p.rol,'rol_crm',e.rol_crm,
    'supervisor_id',e.supervisor_id,'auth_vigente',u.id is not null and u.deleted_at is null
      and u.email_confirmed_at is not null and (u.banned_until is null or u.banned_until<=statement_timestamp())
      and exists(select 1 from auth.identities ai where ai.user_id=p.id and ai.provider='email')) order by p.id)
    into equipo from crm.equipo e join public.perfiles p on p.id=e.perfil_id
    left join auth.users u on u.id=p.id where e.activo and p.activo;
  if equipo is distinct from cfg->'equipo' or exists(select 1 from jsonb_array_elements(equipo) e
    where (e->>'auth_vigente')::boolean is distinct from true) then
    raise exception 'Cambió una cuenta, rol o supervisor' using errcode='P0409';end if;
  if not exists(select 1 from crm.equipo e join public.perfiles p on p.id=e.perfil_id
    where e.perfil_id=(cfg->>'responsable_id')::uuid and e.activo and p.activo and e.rol_crm='gerencia') then
    raise exception 'Responsable operativo no vigente' using errcode='P0409';end if;
  for v_fn in select * from jsonb_to_recordset(cfg->'funciones') x(firma text,huella text,propietario text,acl text) loop
    if not exists(select 1 from pg_proc p where p.oid=to_regprocedure(v_fn.firma)
      and md5(pg_get_functiondef(p.oid))=v_fn.huella and pg_get_userbyid(p.proowner)=v_fn.propietario
      and (p.proacl is null)=(v_fn.acl is null)
      and array(select unnest(string_to_array(trim(both '{}' from p.proacl::text),',')) order by 1)
        =array(select unnest(string_to_array(trim(both '{}' from v_fn.acl),',')) order by 1)) then
      raise exception 'Cambió función/permiso: %',v_fn.firma using errcode='P0409';end if;
  end loop;
  select jsonb_agg(jsonb_build_object('tabla',c.oid::regclass::text,'funcion',t.tgfoid::regprocedure::text,
    'trigger',pg_get_triggerdef(t.oid),'habilitado',t.tgenabled::text)
    order by c.oid::regclass::text collate "C",pg_get_triggerdef(t.oid) collate "C") into triggers
    from pg_trigger t join pg_class c on c.oid=t.tgrelid where not t.tgisinternal
    and c.oid in('crm.multiempresa_flags'::regclass,'crm.piloto_f8_control'::regclass,'crm.piloto_f8_miembros'::regclass);
  if triggers is distinct from cfg->'triggers' then
    raise exception 'Cambió un trigger de configuración o auditoría' using errcode='P0409';end if;
  if exists(select 1 from private.cartera_f5_fuentes_reales() f left join crm.inversionistas i on i.id=f.inversionista_id
    where not coalesce(f.identidad_coherente,false) or i.id is null or i.inversionista_canonico_id is not null) then
    raise exception 'Hay fuentes sin identidad coherente; apertura abortada' using errcode='P0409';end if;
  select count(*),md5(jsonb_agg(to_jsonb(f) order by empresa,fuente_id)::text) into cantidad,antes
    from private.cartera_f5_fuentes_reales() f;
  if cantidad=0 then raise exception 'Sin fuentes para comprobar conservación' using errcode='P0409';end if;
  update crm.piloto_f8_control set activo=false,
    motivo='Apertura general '||(cfg->>'referencia')||'; autorizada por Miguel; ejecución administrativa Codex',
    actualizado_por=(cfg->>'responsable_id')::uuid where singleton;
  update crm.multiempresa_flags set activo=true,actualizado_por=(cfg->>'responsable_id')::uuid
    where nombre in('inversiones_escritura','ficha_360_neutral','postventa_neutral');
  select jsonb_object_agg(nombre,activo) into banderas from crm.multiempresa_flags;
  select c.revision into v_revision from crm.piloto_f8_control c where singleton;
  if banderas is distinct from '{"resolver_en_puertas":true,"inversiones_escritura":true,"ficha_360_neutral":true,"postventa_neutral":true,"metricas_multiempresa_sombra":false}'::jsonb
    or private.piloto_f8_control_activo() then
    raise exception 'No quedó el estado general completo' using errcode='P0409';end if;
  select md5(jsonb_agg(to_jsonb(f) order by empresa,fuente_id)::text) into despues from private.cartera_f5_fuentes_reales() f;
  if despues is distinct from antes then raise exception 'Cambió una fuente durante la transición' using errcode='P0409';end if;
  -- Capacidades efectivas antes del COMMIT: la apertura aborta completa si
  -- cualquiera de las 24 cuentas recibe un resultado distinto de su rol.
  for actor in select * from jsonb_to_recordset(equipo) x(perfil_id uuid,rol_crm text) loop
    perform set_config('request.jwt.claim.sub',actor.perfil_id::text,true);
    perform set_config('request.jwt.claims',jsonb_build_object('sub',actor.perfil_id,'role','authenticated')::text,true);
    f5:=null;f6:=null;error_f5:=null;
    set local role authenticated;
    begin f5:=crm.cartera_inversionistas_estado_fn();exception when others then error_f5:=sqlstate;end;
    f6:=crm.postventa_estado_fn();
    reset role;
    if actor.rol_crm='coordinador' then
      if error_f5 is distinct from '42501' or (f6->>'habilitada')::boolean is distinct from false then
        raise exception 'Coordinación ganó una capacidad indebida' using errcode='P0409';end if;
    elsif error_f5 is not null or (f5->>'habilitada')::boolean is distinct from true
      or (f5->>'escritura_habilitada')::boolean is distinct from true
      or (f6->>'habilitada')::boolean is distinct from true then
      raise exception 'La apertura no habilitó correctamente una cuenta %',actor.rol_crm using errcode='P0409';
    end if;
    roles:=roles||jsonb_build_array(jsonb_build_object('actor',md5('F9-20260915:'||actor.perfil_id::text),
      'rol',actor.rol_crm,'cartera',f5,'postventa',f6,'error_cartera',error_f5));
  end loop;
  perform set_config('request.jwt.claim.sub','',true);perform set_config('request.jwt.claims','{}',true);
  perform set_config('f9.resultado',jsonb_build_object('estado','PASS','referencia',cfg->>'referencia',
    'fecha',statement_timestamp(),'base',current_database(),'banderas',banderas,'revision',v_revision,
    'fuentes',cantidad,'huella_fuentes',despues,'fuentes_conservadas',true,'cuentas',jsonb_array_length(equipo),
    'roles',roles)::text,true);
end;
$f9$;
select current_setting('f9.resultado')::jsonb evidencia;
commit;
