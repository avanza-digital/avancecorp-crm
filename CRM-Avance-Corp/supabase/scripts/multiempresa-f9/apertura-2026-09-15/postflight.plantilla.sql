-- Solo consultas de capacidades con FOR SHARE. El ROLLBACK no revierte la apertura anterior.
begin isolation level read committed;
set local search_path='';
set local statement_timeout='30s';
do $f9_verificar$
declare cfg constant jsonb:='__CONFIG__'::jsonb;
  actor record;f5 jsonb;f6 jsonb;e5 text;e6 text;roles jsonb:='[]';
begin
  if current_user<>'postgres' or auth.uid() is not null then raise exception 'Administración requerida';end if;
  if (select jsonb_object_agg(nombre,activo) from crm.multiempresa_flags) is distinct from
    '{"resolver_en_puertas":true,"inversiones_escritura":true,"ficha_360_neutral":true,"postventa_neutral":true,"metricas_multiempresa_sombra":false}'::jsonb
    or exists(select 1 from crm.piloto_f8_control where activo) then raise exception 'Configuración general incorrecta';end if;
  for actor in select * from jsonb_to_recordset(cfg->'equipo') x(perfil_id uuid,rol_crm text) loop
    perform set_config('request.jwt.claim.sub',actor.perfil_id::text,true);
    perform set_config('request.jwt.claims',jsonb_build_object('sub',actor.perfil_id,'role','authenticated')::text,true);
    f5:=null;f6:=null;e5:=null;e6:=null;
    set local role authenticated;
    begin f5:=crm.cartera_inversionistas_estado_fn();exception when others then e5:=sqlstate;end;
    begin f6:=crm.postventa_estado_fn();exception when others then e6:=sqlstate;end;
    reset role;
    if e6 is not null then raise exception 'Postventa falló para %: %',actor.perfil_id,e6;end if;
    if actor.rol_crm='coordinador' then
      if e5 is distinct from '42501' or (f6->>'habilitada')::boolean is distinct from false then
        raise exception 'Coordinación habilitada indebidamente';end if;
    elsif e5 is not null or (f5->>'habilitada')::boolean is distinct from true
      or (f5->>'escritura_habilitada')::boolean is distinct from true
      or (f6->>'habilitada')::boolean is distinct from true then
      raise exception 'Capacidades incorrectas para %',actor.perfil_id;
    end if;
    roles:=roles||jsonb_build_array(jsonb_build_object('actor',md5('F9-20260915:'||actor.perfil_id::text),
      'rol',actor.rol_crm,'cartera',f5,'postventa',f6,'error_cartera',e5,'error_postventa',e6));
  end loop;
  perform set_config('request.jwt.claim.sub','',true);perform set_config('request.jwt.claims','{}',true);
  perform set_config('f9.postflight',jsonb_build_object('estado','PASS','fase','LECTURA_POSTERIOR_COMMIT',
    'fecha',clock_timestamp(),'roles',roles)::text,true);
end $f9_verificar$;
select current_setting('f9.postflight')::jsonb evidencia;
rollback;
