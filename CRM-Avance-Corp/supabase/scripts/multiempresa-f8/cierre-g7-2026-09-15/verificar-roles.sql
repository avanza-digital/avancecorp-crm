-- Comprueba capacidades SQL de cada cuenta activa, sin iniciar sesión Auth.
-- Las RPC toman bloqueos de filas: READ COMMITTED con ROLLBACK obligatorio.
begin isolation level read committed;
set local statement_timeout='30s';
set local lock_timeout='1s';
set local search_path='';
do $roles$
declare
  a record; f5 jsonb; f6 jsonb; error_f5 text; error_f6 text;
  resultados jsonb:='[]';
begin
  for a in select e.perfil_id,e.rol_crm,
    private.piloto_f8_actor_activo(e.perfil_id) piloto,
    exists(select 1 from auth.users u where u.id=e.perfil_id
      and u.deleted_at is null and u.email_confirmed_at is not null
      and (u.banned_until is null or u.banned_until<=statement_timestamp())
      and exists(select 1 from auth.identities ai where ai.user_id=u.id and ai.provider='email')) cuenta_valida
    from crm.equipo e join public.perfiles p on p.id=e.perfil_id
    where e.activo and p.activo order by e.rol_crm,e.perfil_id
  loop
    f5:=null;f6:=null;error_f5:=null;error_f6:=null;
    perform set_config('request.jwt.claim.sub',a.perfil_id::text,true);
    perform set_config('request.jwt.claims',jsonb_build_object('sub',a.perfil_id,'role','authenticated')::text,true);
    set local role authenticated;
    begin f5:=crm.cartera_inversionistas_estado_fn();
      exception when others then error_f5:=sqlstate; end;
    begin f6:=crm.postventa_estado_fn();
      exception when others then error_f6:=sqlstate; end;
    reset role;
    resultados:=resultados||jsonb_build_array(jsonb_build_object(
      'actor',md5('G7-20260915:'||a.perfil_id::text),'rol',a.rol_crm,
      'piloto',a.piloto,'cuenta_auth_vigente',a.cuenta_valida,
      'cartera',f5,'error_cartera',error_f5,'postventa',f6,'error_postventa',error_f6));
  end loop;
  perform set_config('g7.roles',resultados::text,true);
end;
$roles$;
select jsonb_build_object('corte',statement_timestamp(),'transaction_read_only',current_setting('transaction_read_only'),
  'metodo','Claims SQL locales, SET LOCAL ROLE authenticated y ROLLBACK. No login Auth/HTTP ni navegación humana.',
  'roles',current_setting('g7.roles')::jsonb) evidencia;
rollback;
