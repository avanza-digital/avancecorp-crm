-- Prerrequisito de cotitularidad: el auxiliar no autentica ni autoriza.
-- Crear/actualizar contrato lo llaman como postgres después de sus controles.
-- Se conserva su cuerpo y la congelación documental; se cierra la llamada API.
do $cotitular_guard$
declare v_md5 text;
begin
  v_md5:=md5(pg_get_functiondef('public._sync_contrato_titulares(uuid,jsonb)'::regprocedure));
  if v_md5 is distinct from '833f09e11e2c1289739613074b07965b'
     or (select pg_get_userbyid(proowner) from pg_proc
       where oid='public._sync_contrato_titulares(uuid,jsonb)'::regprocedure) <> 'postgres' then
    raise exception 'Definición del auxiliar distinta de la base revisada (MD5 %); revisar cuerpo, atributos y versión PostgreSQL',v_md5;
  end if;
end;
$cotitular_guard$;
revoke all on function public._sync_contrato_titulares(uuid,jsonb)
  from public,anon,authenticated,service_role;

-- REVOKE no es prueba de su propio resultado: rechazar permisos efectivos o
-- grantees inesperados, incluso si el ejecutor recibió únicamente un WARNING.
do $cotitular_acl$
begin
  if exists (select 1 from pg_proc p,
      aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
    where p.oid='public._sync_contrato_titulares(uuid,jsonb)'::regprocedure
      and a.grantee<>p.proowner and a.privilege_type='EXECUTE')
    or exists (select 1 from unnest(array['anon','authenticated','service_role']) rol
      where has_function_privilege(rol,'public._sync_contrato_titulares(uuid,jsonb)','EXECUTE')) then
    raise exception 'El auxiliar de titulares conserva EXECUTE fuera de su propietario'
      using errcode='42501';
  end if;
end;
$cotitular_acl$;
