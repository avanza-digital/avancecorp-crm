begin read only;
do $prueba$
declare
  v_actor uuid;
  v_otro uuid;
  v_rol text;
  v_error text;
begin
  if current_setting('transaction_read_only') <> 'on' then
    raise exception 'La prueba exige solo lectura';
  end if;
  if (select md5(prosrc) from pg_proc where oid=to_regprocedure('crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text,text)'))
      is distinct from '145b30a30e69807a1838c1b960a0675d' then
    raise exception 'Huella productiva inesperada';
  end if;
  raise notice 'PASS: huella productiva coincide con la rama ensayada';
  foreach v_rol in array array['supervisor','vendedor','gerencia'] loop
    select e.perfil_id into strict v_actor from crm.equipo e
      join public.perfiles p on p.id=e.perfil_id
      where e.rol_crm::text=v_rol and e.activo and p.activo order by e.perfil_id limit 1;
    select e.perfil_id into strict v_otro from crm.equipo e
      join public.perfiles p on p.id=e.perfil_id
      where e.perfil_id<>v_actor and e.rol_crm='supervisor' and e.activo and p.activo
      order by e.perfil_id limit 1;
    perform set_config('request.jwt.claim.sub',v_actor::text,true);
    perform set_config('request.jwt.claim.role','authenticated',true);
    perform set_config('request.jwt.claims',jsonb_build_object('sub',v_actor,'role','authenticated')::text,true);
    execute 'set local role authenticated';
    v_error:=null;
    begin
      perform crm.crear_lead_si_disponible(
        p_nombre_completo=>'PRUEBA PERMISO SIN ESCRITURA',p_telefono=>'900888888',
        p_origen=>'referido',p_monto_estimado=>20000,p_moneda=>'PEN',p_vendedor_id=>v_otro);
    exception when insufficient_privilege then v_error:=sqlstate;
    end;
    execute 'reset role';
    if v_error is distinct from '42501' then raise exception 'No rechazó al rol %',v_rol; end if;
    raise notice 'PASS: % no registra Referido con responsable ajeno [42501]',v_rol;
  end loop;
  perform set_config('request.jwt.claim.sub','',true);
  perform set_config('request.jwt.claim.role','anon',true);
  perform set_config('request.jwt.claims','{"role":"anon"}',true);
  execute 'set local role anon';
  v_error:=null;
  begin
    perform crm.crear_lead_si_disponible(
      p_nombre_completo=>'PRUEBA PERMISO SIN ESCRITURA',p_telefono=>'900888888',
      p_origen=>'referido',p_monto_estimado=>20000,p_moneda=>'PEN');
  exception when insufficient_privilege then v_error:=sqlstate;
  end;
  execute 'reset role';
  if v_error is distinct from '42501' then raise exception 'No rechazó anon'; end if;
  raise notice 'PASS: anon no registra Referido [42501]';
  if exists(select 1 from public.perfiles where correo like '%@referidos.example.invalid') then
    raise exception 'Hay identidades del banco en producción';
  end if;
  raise notice 'PASS: no hay identidades sintéticas del banco en producción';
end $prueba$;
rollback;
