-- AVANCECORP: identidad interna para las inversiones de dueños y colaboradores de alto rango
-- (pedido de Miguel, 28/09/2026). No es un analista real: ningún contrato suyo se atribuye a
-- nadie del área comercial.
--
-- Qué crea, en UNA transacción:
--   1. Usuario de acceso en auth (obligatorio: perfiles.id → auth.users) con contraseña
--      aleatoria que nadie conoce. Si algún día hace falta entrar, se restablece desde
--      Portal → Equipo.
--   2. Perfil del portal con rol 'analista' y activo: así aparece en el selector de analista
--      de Portal → Clientes (lista perfiles activos con rol analista/admin/superadmin/comercial).
--   3. Fila en crm.equipo como SUPERVISOR activo, sin supervisor ni analistas a cargo:
--      · public.crear_contrato exige que el asesor de una renovación/upgrade sea vendedor o
--        supervisor activo del equipo; sin esta fila el servidor rechaza esas operaciones.
--      · No puede ser vendedor: private.validar_supervisor_usuario_crm obliga a todo vendedor
--        activo a tener supervisor, y con supervisor entraría al roster de Metas/Ranking.
--      · Metas y Ranking solo nombran a vendedores con supervisor activo
--        (private.roster_metas_vendedores): un supervisor queda fuera de filas y metas.
--      · El reparto de leads solo ofrece vendedores activos; no tiene leads, así que no entra
--        en conversión; los demás supervisores no ven su cartera.
--      · El par Portal analista ↔ CRM supervisor está declarado en private.pares_autoridad
--        («supervisora que además lleva cartera propia»).
--      · Gerencia lo ve solo en «Producción fuera del ranking» (motivo supervisor) y su capital
--        SÍ suma al total de empresa (decisión D8, 27/08/2026) hasta que Miguel decida una
--        exclusión de identidad interna en el núcleo.
--
-- Uso (Miguel, con `!`):
--   supabase db query --linked --file supabase/scripts/avancecorp-identidad-interna.sql
-- Primera pasada con v_ensayo = true: ejecuta todo y termina en `raise`, así NO escribe nada.
-- Segunda pasada con v_ensayo = false: escribe.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $avancecorp$
declare
  v_ensayo   boolean := true;              -- ← cambiar a false para escribir
  v_nombre   constant text := 'AVANCECORP';
  v_correo   constant text := 'avancecorp@miavance.com';
  v_cargo    constant text := 'Inversiones internas';
  v_id       uuid := gen_random_uuid();
  v_fila     record;
begin
  -- CANDADO 1: no existe ya un perfil con ese nombre (activo o no).
  if exists (select 1 from public.perfiles p where upper(btrim(p.nombre_completo)) = v_nombre) then
    raise exception 'CANDADO 1: ya existe un perfil llamado %', v_nombre;
  end if;
  -- CANDADO 2: el correo está libre en auth.
  if exists (select 1 from auth.users u where lower(u.email) = v_correo) then
    raise exception 'CANDADO 2: el correo % ya existe en auth.users', v_correo;
  end if;
  -- CANDADO 3: el modelo sigue siendo el que este script asume.
  if not exists (
    select 1 from pg_constraint c
    where c.conrelid = 'public.perfiles'::regclass and c.conname = 'perfiles_rol_check'
      and pg_get_constraintdef(c.oid) like '%analista%'
  ) then
    raise exception 'CANDADO 3: perfiles_rol_check ya no admite analista; revisar';
  end if;
  if to_regprocedure('private.roster_metas_vendedores()') is null then
    raise exception 'CANDADO 3: falta private.roster_metas_vendedores(); revisar el roster';
  end if;
  if to_regprocedure('private.par_autoridad_valido(text,text)') is not null
     and not private.par_autoridad_valido('analista', 'supervisor') then
    raise exception 'CANDADO 3: el par Portal analista / CRM supervisor ya no está declarado';
  end if;

  -- 1. Usuario de acceso, sin contraseña usable (hash de 32 bytes aleatorios).
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new, email_change,
    email_change_token_current, phone_change, phone_change_token, reauthentication_token
  ) values (
    '00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated', v_correo,
    extensions.crypt(encode(extensions.gen_random_bytes(32), 'hex'), extensions.gen_salt('bf')),
    now(), '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('nombre', v_nombre), now(), now(),
    '', '', '', '', '', '', '', ''
  );
  insert into auth.identities (id, user_id, provider_id, provider, identity_data, created_at, updated_at)
  values (
    gen_random_uuid(), v_id, v_id::text, 'email',
    jsonb_build_object('sub', v_id::text, 'email', v_correo, 'email_verified', true, 'phone_verified', false),
    now(), now()
  );

  -- 2. Perfil del portal: analista activo, sin documento (no es una persona).
  insert into public.perfiles (id, nombre_completo, rol, activo, correo, cargo, tipo_documento, dni)
  values (v_id, v_nombre, 'analista', true, v_correo, v_cargo, 'DNI', null);

  -- 3. Equipo del CRM: supervisor activo, sin supervisor ni analistas.
  insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo)
  values (v_id, 'supervisor', null, true);

  -- VERIFICACIÓN: aparece donde debe y no donde no debe.
  select p.rol, p.activo, e.rol_crm, e.supervisor_id, e.activo as equipo_activo
    into v_fila
  from public.perfiles p join crm.equipo e on e.perfil_id = p.id
  where p.id = v_id;
  if v_fila.rol <> 'analista' or not v_fila.activo
     or v_fila.rol_crm <> 'supervisor' or v_fila.supervisor_id is not null or not v_fila.equipo_activo then
    raise exception 'VERIFICACIÓN: la fila no quedó como analista activo + supervisor activo sin supervisor (%)', v_fila;
  end if;
  -- Mismo predicado que public.crear_contrato para aceptar al dueño de una renovación/upgrade.
  if not exists (
    select 1 from crm.equipo e
    where e.perfil_id = v_id and e.activo and e.rol_crm in ('vendedor', 'supervisor')
  ) then
    raise exception 'VERIFICACIÓN: crear_contrato no lo aceptaría como dueño de cartera';
  end if;
  if exists (select 1 from private.roster_metas_vendedores() r where r.vendedor_id = v_id) then
    raise exception 'VERIFICACIÓN: AVANCECORP entró al roster de Metas/Ranking; no debe';
  end if;
  if private.rol_crm(v_id) is distinct from 'supervisor' then
    raise exception 'VERIFICACIÓN: private.rol_crm no lo resuelve como supervisor (%)', private.rol_crm(v_id);
  end if;

  raise notice 'AVANCECORP listo: perfil % · correo % · analista activo · supervisor sin equipo', v_id, v_correo;
  if v_ensayo then
    raise exception 'ENSAYO OK: todo pasa y nada se escribió (v_ensayo = true). Cambia a false para aplicar.';
  end if;
end
$avancecorp$;

commit;

-- Reversión (solo si nunca llegó a tener clientes ni contratos):
--   delete from crm.equipo where perfil_id = (select id from public.perfiles where nombre_completo = 'AVANCECORP');
--   delete from public.perfiles where nombre_completo = 'AVANCECORP';
--   delete from auth.users where email = 'avancecorp@miavance.com';
-- Si ya tiene cartera, NO borrar: desactivar (perfiles.activo = false y crm.equipo.activo = false).
