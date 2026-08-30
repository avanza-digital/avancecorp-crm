-- P-055 · Cierre de sesión de las TRES cuentas de prueba revocadas (2026-08-30).
-- Decisión de Miguel: cerrarlas las tres. Son alias de su propio correo
-- (avancecorp26+crm-*), no personal. Reversible: ver el guion de reapertura.
begin;
set local lock_timeout = '5s';

do $$
declare
  v_ids uuid[] := array[
    'd81aca5b-e39e-42d7-b723-1a44930145b8',  -- GERENTE CRM (DEMO)
    '0c7ffc92-260a-4f87-b2fe-a732740c8d17',  -- ANALISTA CRM (DEMO)
    '3a4f3c2a-271d-478c-8625-16225e932c46'   -- SUPERVISOR CRM (DEMO)
  ];
  v_id uuid; v_correo text; v_n integer;
begin
  -- Preflight: las tres tienen que ser cuentas +crm- y estar revocadas.
  foreach v_id in array v_ids loop
    select p.correo into v_correo from public.perfiles p where p.id = v_id;
    if v_correo is null or v_correo not like 'avancecorp26+crm-%' then
      raise exception 'Preflight: % no es una cuenta de prueba (correo %)', v_id, coalesce(v_correo, '(no existe)');
    end if;
    if exists (select 1 from crm.equipo e where e.perfil_id = v_id and e.activo is true) then
      raise exception 'Preflight: % no esta revocada en el CRM', v_correo;
    end if;
  end loop;

  update public.perfiles set activo = false where id = any(v_ids);
  update auth.refresh_tokens set revoked = true where user_id = any(select unnest(v_ids)::text) and revoked is false;
  delete from auth.sessions where user_id = any(v_ids);
  update auth.users set banned_until = 'infinity'::timestamptz where id = any(v_ids);

  select count(*) into v_n from public.perfiles where id = any(v_ids) and activo is not false;
  if v_n <> 0 then raise exception 'Postflight: % perfiles siguen activos', v_n; end if;
  select count(*) into v_n from auth.sessions where user_id = any(v_ids);
  if v_n <> 0 then raise exception 'Postflight: quedan % sesiones abiertas', v_n; end if;
  select count(*) into v_n from auth.refresh_tokens where user_id = any(select unnest(v_ids)::text) and revoked is false;
  if v_n <> 0 then raise exception 'Postflight: quedan % llaves vivas', v_n; end if;
  select count(*) into v_n from auth.users where id = any(v_ids) and banned_until is null;
  if v_n <> 0 then raise exception 'Postflight: % cuentas sin bloquear', v_n; end if;
end $$;

commit;

select p.nombre_completo, p.correo, p.activo as perfil_activo, u.banned_until is not null as bloqueada,
       (select count(*) from auth.sessions s where s.user_id = p.id) as sesiones,
       (select count(*) from auth.refresh_tokens r where r.user_id = p.id::text and r.revoked is false) as llaves_vivas
  from public.perfiles p
  join crm.equipo e on e.perfil_id = p.id
  left join auth.users u on u.id = p.id
 where e.activo is false
 order by p.nombre_completo;
