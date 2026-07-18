-- Oraculo transaccional de crm.agenda_ics (suscripcion ICS) — patron 4A-4C.
--
-- Se ejecuta SOLO contra un branch con la migracion 20260718120243 aplicada.
-- TODO corre en una unica transaccion que SIEMPRE se revierte: el exito es el
-- error final 'AGENDA_ICS_TX_OK' (cualquier otro error = fallo real).
--
-- Cubre: cada quien SU fila (SELECT/INSERT/UPDATE), token ajeno invisible
-- incluso para su supervisor, rotacion cambia el token, DELETE denegado por
-- grant, y el WITH CHECK que impide crear filas a nombre de otro.

begin;

-- ── Fixtures minimos (como postgres; UUIDs fijos del oraculo) ────────────────
-- S1 (supervisor) -> V1 (vendedor): el supervisor NO debe ver el token de V1.

insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, confirmation_token, recovery_token,
                        email_change_token_new, email_change)
select '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated',
       u.email, '', now(), '', '', '', ''
from (values
  ('aaaa0000-0000-4000-8000-000000000012'::uuid, 'oraculo-ics-s1@test.local'),
  ('aaaa0000-0000-4000-8000-000000000014'::uuid, 'oraculo-ics-v1@test.local')
) as u(id, email);

insert into public.perfiles (id, nombre_completo, rol, activo)
values
  ('aaaa0000-0000-4000-8000-000000000012', 'ORACULO ICS SUPERVISOR', 'comercial', true),
  ('aaaa0000-0000-4000-8000-000000000014', 'ORACULO ICS VENDEDOR',   'comercial', true);

insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo)
values
  ('aaaa0000-0000-4000-8000-000000000012', 'supervisor', null, true),
  ('aaaa0000-0000-4000-8000-000000000014', 'vendedor',
   'aaaa0000-0000-4000-8000-000000000012', true);

-- ── Sesion V1 (vendedor): crea, ve y rota SOLO su fila ───────────────────────
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"aaaa0000-0000-4000-8000-000000000014","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'aaaa0000-0000-4000-8000-000000000014', true);

-- Crear la fila propia genera token solo.
do $$
declare v_token uuid;
begin
  insert into crm.agenda_ics (perfil_id)
  values ('aaaa0000-0000-4000-8000-000000000014')
  returning token into v_token;
  if v_token is null then
    raise exception 'FALLO insert: la fila propia no genero token';
  end if;
end $$;

-- Crear una fila A NOMBRE DE OTRO esta vetado (WITH CHECK).
do $$
begin
  begin
    insert into crm.agenda_ics (perfil_id)
    values ('aaaa0000-0000-4000-8000-000000000012');
    raise exception 'FALLO WITH CHECK: pudo crear la fila de otro';
  exception when insufficient_privilege or check_violation then
    null; -- veto esperado (RLS)
  end;
end $$;

-- Rotar cambia el token y solo toca la fila propia.
do $$
declare v_antes uuid; v_despues uuid; v_n int;
begin
  select token into v_antes from crm.agenda_ics
   where perfil_id = 'aaaa0000-0000-4000-8000-000000000014';
  update crm.agenda_ics
     set token = gen_random_uuid(), rotado_en = now()
   where perfil_id = 'aaaa0000-0000-4000-8000-000000000014'
  returning token into v_despues;
  get diagnostics v_n = row_count;
  if v_n <> 1 or v_despues is null or v_despues = v_antes then
    raise exception 'FALLO rotacion: el token no cambio (filas=%, antes=%, despues=%)',
      v_n, v_antes, v_despues;
  end if;
end $$;

-- DELETE esta denegado por grant (dejar de compartir = rotar).
do $$
begin
  begin
    delete from crm.agenda_ics
     where perfil_id = 'aaaa0000-0000-4000-8000-000000000014';
    raise exception 'FALLO grants: DELETE deberia estar denegado';
  exception when insufficient_privilege then
    null; -- denegacion esperada
  end;
end $$;

reset role;

-- ── Sesion S1 (supervisor): el token de su vendedor le es INVISIBLE ──────────
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"aaaa0000-0000-4000-8000-000000000012","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'aaaa0000-0000-4000-8000-000000000012', true);

do $$
declare v_n int;
begin
  select count(*) into v_n from crm.agenda_ics;
  if v_n <> 0 then
    raise exception 'FALLO RLS S1: ve % fila(s) ajenas — el token de un vendedor es privado', v_n;
  end if;
  -- Tampoco la alcanza por UPDATE (0 filas, RLS la oculta).
  update crm.agenda_ics set rotado_en = now()
   where perfil_id = 'aaaa0000-0000-4000-8000-000000000014';
  get diagnostics v_n = row_count;
  if v_n <> 0 then
    raise exception 'FALLO RLS S1: pudo tocar la fila de su vendedor';
  end if;
  -- Su propia fila si funciona.
  insert into crm.agenda_ics (perfil_id)
  values ('aaaa0000-0000-4000-8000-000000000012');
  select count(*) into v_n from crm.agenda_ics;
  if v_n <> 1 then
    raise exception 'FALLO RLS S1: esperaba ver solo SU fila, vio %', v_n;
  end if;
end $$;

reset role;

-- ── Como postgres: las 2 filas existen (nada se filtro por accidente) ────────
do $$
declare v_n int;
begin
  select count(*) into v_n from crm.agenda_ics
   where perfil_id in ('aaaa0000-0000-4000-8000-000000000012',
                       'aaaa0000-0000-4000-8000-000000000014');
  if v_n <> 2 then
    raise exception 'FALLO integridad: esperaba 2 filas del oraculo, hay %', v_n;
  end if;
end $$;

-- Exito = este error exacto (revierte TODA la transaccion; cero fixtures).
do $$ begin raise exception 'AGENDA_ICS_TX_OK'; end $$;
