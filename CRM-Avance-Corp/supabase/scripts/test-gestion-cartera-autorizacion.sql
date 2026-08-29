-- Gate transaccional de la autorización de Gestión de cartera.
-- Requiere 20260828210351. Usa fixtures demo y transitorios; revierte todo.

begin;
set local lock_timeout = '10s';
set local statement_timeout = '30s';

select set_config(
  'gcar.vend1',
  (select id::text from public.perfiles where correo = 'vend1.crm@demo.avancecorp.pe'),
  true
);
select set_config(
  'gcar.vend2',
  (select id::text from public.perfiles where correo = 'vend2.crm@demo.avancecorp.pe'),
  true
);
select set_config(
  'gcar.vend3',
  (select id::text from public.perfiles where correo = 'vend3.crm@demo.avancecorp.pe'),
  true
);
select set_config(
  'gcar.sup1',
  (select id::text from public.perfiles where correo = 'sup1.crm@demo.avancecorp.pe'),
  true
);
select set_config(
  'gcar.directorio',
  (select id::text from public.perfiles where correo = 'directorio.crm@demo.avancecorp.pe'),
  true
);
select set_config(
  'gcar.gerencia',
  (select id::text from public.perfiles where correo = 'gerencia.crm@demo.avancecorp.pe'),
  true
);
select set_config(
  'gcar.cliente',
  (select id::text from public.perfiles where correo = 'cliente-bancario.crm@demo.avancecorp.pe'),
  true
);
select set_config('gcar.tarea', gen_random_uuid()::text, true);
select set_config('gcar.tarea_analista', gen_random_uuid()::text, true);

-- El caso de privacidad necesita un valor real en el origen: una aserción
-- `domicilio is null` sobre un fixture vacío no demostraría redacción alguna.
-- La transacción completa termina en ROLLBACK.
update public.perfiles
 set domicilio = coalesce(
     nullif(btrim(domicilio), ''),
     'Av. Validación Gestión de cartera 123, Lima'
   )
 where id = nullif(current_setting('gcar.cliente', true), '')::uuid;

do $precondiciones$
begin
  if current_setting('gcar.vend1', true) is null
     or current_setting('gcar.vend2', true) is null
     or current_setting('gcar.vend3', true) is null
     or current_setting('gcar.sup1', true) is null
     or current_setting('gcar.directorio', true) is null
     or current_setting('gcar.gerencia', true) is null
     or current_setting('gcar.cliente', true) is null then
    raise exception 'GCAR-A01: faltan fixtures demo';
  end if;

  if not exists (
    select 1
    from public.perfiles p
    where p.id = current_setting('gcar.cliente')::uuid
      and p.asesor_perfil_id = current_setting('gcar.vend1')::uuid
      and p.banco is not null and p.cci is not null
      and p.domicilio is not null
  ) then
    raise exception 'GCAR-A02: el cliente bancario no pertenece a vend1 o no tiene banca/domicilio';
  end if;
end;
$precondiciones$;

-- La misma identidad no puede recibir autoridad operativa de Gerencia y sí
-- puede quedar enrolada con su capacidad canónica de Directorio.
do $invariante_directorio$
declare
  v_aceptada boolean := false;
begin
  if exists (
    select 1 from crm.equipo
    where perfil_id = current_setting('gcar.directorio')::uuid
  ) then
    raise exception 'GCAR-A03: el fixture esperaba Directorio sin membresía previa';
  end if;

  begin
    insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo)
    values (current_setting('gcar.directorio')::uuid, 'gerencia', null, true);
    v_aceptada := true;
  exception when raise_exception or check_violation then
    null;
  end;
  if v_aceptada then
    raise exception 'GCAR-A04: Directorio Portal fue aceptado como Gerencia CRM';
  end if;

  insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo)
  values (current_setting('gcar.directorio')::uuid, 'directorio', null, true);

  if private.rol_crm(current_setting('gcar.directorio')::uuid) is distinct from 'directorio' then
    raise exception 'GCAR-A05: la pareja Directorio/Directorio no produce el rol efectivo';
  end if;

  v_aceptada := false;
  begin
    update public.perfiles
       set rol = 'comercial'
     where id = current_setting('gcar.directorio')::uuid;
    v_aceptada := true;
  exception when raise_exception or check_violation then
    null;
  end;
  if v_aceptada then
    raise exception 'GCAR-A06: el Portal pudo abandonar Directorio con membresía Directorio activa';
  end if;
end;
$invariante_directorio$;

-- Supervisor: detalle completo de un cliente del equipo y alta de tarea. Este
-- era el 42501 reproducible porque tareas_insert consultaba perfiles bajo RLS.
select set_config('request.jwt.claims', '{"role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', current_setting('gcar.sup1'), true);
set local role authenticated;

do $supervisor$
declare
  v_detalle record;
  v_vendedor uuid;
begin
  select * into v_detalle
  from crm.cliente_detalle_fn(current_setting('gcar.cliente')::uuid);
  if not found
     or v_detalle.domicilio is null
     or v_detalle.banca_visible is not true
     or v_detalle.cuentas_bancarias_visibles is not true
     or v_detalle.banco is null
     or v_detalle.cci is null then
    raise exception 'GCAR-A07: Supervisor no recibió el detalle bancario de su equipo';
  end if;

  insert into crm.tareas (
    id, perfil_id, creado_por, tipo, titulo, vence_en
  ) values (
    current_setting('gcar.tarea')::uuid,
    current_setting('gcar.cliente')::uuid,
    auth.uid(),
    'tarea',
    'GESTIÓN CARTERA AUTORIZACIÓN TX',
    now() + interval '1 day'
  ) returning vendedor_id into v_vendedor;

  if v_vendedor is distinct from current_setting('gcar.vend1')::uuid then
    raise exception 'GCAR-A08: la tarea no quedó anclada al analista canónico';
  end if;
end;
$supervisor$;

reset role;

-- Analista: el BEFORE deriva también el supervisor canónico. La policy debe
-- aceptar esa pareja aun cuando el analista solo se vea a sí mismo en
-- vendedor_ids_visibles(). Este INSERT corre con el rol SQL real del API.
select set_config('request.jwt.claim.sub', current_setting('gcar.vend1'), true);
set local role authenticated;

do $analista_tarea_cliente$
declare
  v_vendedor uuid;
  v_supervisor uuid;
begin
  insert into crm.tareas (
    id, perfil_id, creado_por, tipo, titulo, vence_en
  ) values (
    current_setting('gcar.tarea_analista')::uuid,
    current_setting('gcar.cliente')::uuid,
    auth.uid(),
    'tarea',
    'GESTIÓN CARTERA ANALISTA AUTORIZADO TX',
    now() + interval '1 day'
  ) returning vendedor_id, asignado_supervisor_id
    into v_vendedor, v_supervisor;

  if v_vendedor is distinct from current_setting('gcar.vend1')::uuid
     or v_supervisor is distinct from current_setting('gcar.sup1')::uuid then
    raise exception 'GCAR-A26: el Analista no conservó vendedor_id=self + supervisor canónico';
  end if;
end;
$analista_tarea_cliente$;

-- El Analista sí puede actualizar los únicos campos que el navegador usa para
-- su agenda, pero ningún actor autenticado puede reescribir la tenencia técnica.
do $analista_update_agenda$
declare
  v_filas integer;
begin
  update crm.tareas
     set vence_en = now() + interval '2 days', confirmada_en = null
   where id = current_setting('gcar.tarea_analista')::uuid;
  get diagnostics v_filas = row_count;
  if v_filas <> 1 then
    raise exception 'GCAR-A27: el Analista no pudo actualizar vencimiento/confirmación de su tarea';
  end if;
end;
$analista_update_agenda$;

reset role;
select set_config('request.jwt.claim.sub', current_setting('gcar.sup1'), true);
set local role authenticated;

do $supervisor_no_tenencia$
declare
  v_aceptada boolean := false;
begin
  begin
    update crm.tareas
       set vendedor_id = current_setting('gcar.vend2')::uuid
     where id = current_setting('gcar.tarea')::uuid;
    v_aceptada := true;
  exception when insufficient_privilege then
    null;
  end;
  if v_aceptada then
    raise exception 'GCAR-A28: authenticated pudo reescribir la tenencia de una tarea';
  end if;
end;
$supervisor_no_tenencia$;

reset role;

-- Otro árbol no descubre siquiera la existencia del cliente por la RPC.
select set_config('request.jwt.claim.sub', current_setting('gcar.vend3'), true);
set local role authenticated;

do $ajeno$
begin
  if exists (
    select 1
    from crm.cliente_detalle_fn(current_setting('gcar.cliente')::uuid)
  ) then
    raise exception 'GCAR-A09: Analista ajeno obtuvo el detalle';
  end if;
end;
$ajeno$;

reset role;

-- Directorio: identidad global, banca redactada, tabla cruda oculta y ninguna
-- posibilidad de fabricar tareas aunque conozca los UUID.
select set_config('request.jwt.claim.sub', current_setting('gcar.directorio'), true);
set local role authenticated;

do $directorio$
declare
  v_detalle record;
  v_aceptada boolean := false;
begin
  select * into v_detalle
  from crm.cliente_detalle_fn(current_setting('gcar.cliente')::uuid);
  if not found
     or v_detalle.nombre_completo is null
     or v_detalle.domicilio is not null
     or v_detalle.banca_visible is not false
     or v_detalle.cuentas_bancarias_visibles is not false
     or v_detalle.banco is not null
     or v_detalle.numero_cuenta is not null
     or v_detalle.cci is not null
     or v_detalle.banco_usd is not null
     or v_detalle.numero_cuenta_usd is not null
     or v_detalle.cci_usd is not null
     or v_detalle.beneficiario_nombre is not null
     or v_detalle.beneficiario_nombre_usd is not null then
    raise exception 'GCAR-A10: Directorio no recibió una proyección correctamente redactada';
  end if;

  if exists (
    select 1 from public.perfiles
    where id = current_setting('gcar.cliente')::uuid
  ) then
    raise exception 'GCAR-A11: Directorio todavía lee el perfil crudo del cliente';
  end if;

  begin
    insert into crm.tareas (
      id, perfil_id, creado_por, tipo, titulo, vence_en
    ) values (
      gen_random_uuid(),
      current_setting('gcar.cliente')::uuid,
      auth.uid(),
      'tarea',
      'DIRECTORIO NO DEBE CREAR',
      now() + interval '1 day'
    );
    v_aceptada := true;
  exception when insufficient_privilege then
    null;
  end;
  if v_aceptada then
    raise exception 'GCAR-A12: Directorio creó una tarea';
  end if;
end;
$directorio$;

reset role;

-- Defensa en profundidad: incluso si una escritura privilegiada eludiera los
-- triggers, una pareja Portal/CRM desalineada no recupera rol ni lectura
-- global. session_replication_role se usa solo para fabricar el estado que las
-- rutas normales prohíben; todo vive dentro de esta transacción.
set local session_replication_role = replica;
update crm.equipo
   set rol_crm = 'gerencia', supervisor_id = null
 where perfil_id = current_setting('gcar.directorio')::uuid;
set local session_replication_role = origin;

select set_config('request.jwt.claim.sub', current_setting('gcar.directorio'), true);
set local role authenticated;
do $fail_closed_crm_desalineado$
begin
  if private.rol_crm(current_setting('gcar.directorio')::uuid) is not null
     or private.es_lector_global()
     or exists (
       select 1
       from crm.cliente_detalle_fn(current_setting('gcar.cliente')::uuid)
     ) then
    raise exception 'GCAR-A17: Directorio Portal + Gerencia CRM no falló cerrado';
  end if;
end;
$fail_closed_crm_desalineado$;
reset role;

set local session_replication_role = replica;
update crm.equipo
   set rol_crm = 'directorio', supervisor_id = null
 where perfil_id = current_setting('gcar.directorio')::uuid;
update public.perfiles
   set rol = 'comercial'
 where id = current_setting('gcar.directorio')::uuid;
set local session_replication_role = origin;

select set_config('request.jwt.claim.sub', current_setting('gcar.directorio'), true);
set local role authenticated;
do $fail_closed_portal_desalineado$
begin
  if private.rol_crm(current_setting('gcar.directorio')::uuid) is not null
     or private.es_lector_global()
     or exists (
       select 1
       from crm.cliente_detalle_fn(current_setting('gcar.cliente')::uuid)
     ) then
    raise exception 'GCAR-A18: Directorio CRM + Portal comercial no falló cerrado';
  end if;
end;
$fail_closed_portal_desalineado$;
reset role;

set local session_replication_role = replica;
update public.perfiles
   set rol = 'directorio'
 where id = current_setting('gcar.directorio')::uuid;
set local session_replication_role = origin;

-- Una membresía Directorio presente pero inactiva es una revocación. No debe
-- activar el fallback histórico reservado a Directorio sin ninguna membresía.
update crm.equipo
   set activo = false
 where perfil_id = current_setting('gcar.directorio')::uuid;

select set_config('request.jwt.claim.sub', current_setting('gcar.directorio'), true);
set local role authenticated;
do $fail_closed_membresia_inactiva$
begin
  if private.rol_crm(current_setting('gcar.directorio')::uuid) is not null
     or private.es_lector_global()
     or exists (
       select 1
       from crm.cliente_detalle_fn(current_setting('gcar.cliente')::uuid)
     ) then
    raise exception 'GCAR-A19: la membresía Directorio inactiva recuperó lectura global';
  end if;
end;
$fail_closed_membresia_inactiva$;
reset role;

update crm.equipo
   set activo = true
 where perfil_id = current_setting('gcar.directorio')::uuid;

-- Las casillas bancarias históricas y el ledger son capacidades distintas.
-- Gerencia conserva la proyección cruda de un cliente inactivo, pero el ledger
-- exige cliente activo: este caso evita volver a derivar un flag del otro.
update public.perfiles
   set activo = false
 where id = current_setting('gcar.cliente')::uuid;

select set_config('request.jwt.claim.sub', current_setting('gcar.gerencia'), true);
set local role authenticated;
do $cliente_inactivo_flags_separados$
declare
  v_detalle record;
begin
  select * into v_detalle
  from crm.cliente_detalle_fn(current_setting('gcar.cliente')::uuid);
  if not found
     or v_detalle.domicilio is null
     or v_detalle.banca_visible is not true
     or v_detalle.cuentas_bancarias_visibles is not false
     or v_detalle.banco is null
     or v_detalle.cci is null then
    raise exception 'GCAR-A20: los flags bancarios del cliente inactivo no quedaron separados';
  end if;
end;
$cliente_inactivo_flags_separados$;
reset role;

update public.perfiles
   set activo = true
 where id = current_setting('gcar.cliente')::uuid;

-- Transiciones de rol: las responsabilidades activas se validan también al
-- cambiar rol, no solamente al desactivar una membresía. Los UUID son fixtures
-- transitorios y el ROLLBACK final los elimina.
insert into auth.users (
  id, aud, role, email, email_confirmed_at, raw_app_meta_data,
  raw_user_meta_data, created_at, updated_at
)
values
  ('7fa10000-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
   'gcar-transicion-analista@test.invalid', now(), '{}', '{}', now(), now()),
  ('7fa20000-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
   'gcar-transicion-cliente@test.invalid', now(), '{}', '{}', now(), now());

insert into public.perfiles (
  id, nombre_completo, correo, rol, activo, asesor_perfil_id, creado_por
)
values
  ('7fa10000-0000-4000-8000-000000000001', 'GCAR TRANSICION ANALISTA',
   'gcar-transicion-analista@test.invalid', 'comercial', true, null,
   current_setting('gcar.gerencia')::uuid),
  ('7fa20000-0000-4000-8000-000000000001', 'GCAR TRANSICION CLIENTE',
   'gcar-transicion-cliente@test.invalid', 'cliente', true,
   '7fa10000-0000-4000-8000-000000000001',
   '7fa10000-0000-4000-8000-000000000001');

insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo, creado_por)
values (
  '7fa10000-0000-4000-8000-000000000001', 'vendedor',
  current_setting('gcar.sup1')::uuid, true,
  current_setting('gcar.gerencia')::uuid
);

insert into crm.tareas (
  id, perfil_id, creado_por, tipo, titulo, vence_en
) values (
  '7fa30000-0000-4000-8000-000000000001',
  '7fa20000-0000-4000-8000-000000000001',
  '7fa10000-0000-4000-8000-000000000001',
  'tarea', 'GCAR TRANSICIÓN CON RESPONSABILIDADES', now() + interval '1 day'
);

do $transiciones_analista$
declare
  v_fallo boolean := false;
  v_mensaje text;
begin
  begin
    update crm.equipo
       set rol_crm = 'gerencia', supervisor_id = null
     where perfil_id = '7fa10000-0000-4000-8000-000000000001';
  exception when raise_exception then
    get stacked diagnostics v_mensaje = message_text;
    v_fallo := v_mensaje like '%clientes asignados%';
  end;
  if not v_fallo then
    raise exception 'GCAR-A21: el cambio Analista→Gerencia no quedó bloqueado por cliente activo: %',
      coalesce(v_mensaje, 'sin error');
  end if;

  update public.perfiles
     set activo = false
   where id = '7fa20000-0000-4000-8000-000000000001';

  v_fallo := false;
  v_mensaje := null;
  begin
    update crm.equipo
       set rol_crm = 'gerencia', supervisor_id = null
     where perfil_id = '7fa10000-0000-4000-8000-000000000001';
  exception when raise_exception then
    get stacked diagnostics v_mensaje = message_text;
    v_fallo := v_mensaje like '%tareas comerciales pendientes%';
  end;
  if not v_fallo then
    raise exception 'GCAR-A22: el cambio Analista→Gerencia no quedó bloqueado por tarea pendiente: %',
      coalesce(v_mensaje, 'sin error');
  end if;

  delete from crm.tareas
  where id = '7fa30000-0000-4000-8000-000000000001';

  update crm.equipo
     set rol_crm = 'gerencia', supervisor_id = null
   where perfil_id = '7fa10000-0000-4000-8000-000000000001';
  if private.rol_crm('7fa10000-0000-4000-8000-000000000001')
       is distinct from 'gerencia' then
    raise exception 'GCAR-A23: la transición limpia Analista→Gerencia fue rechazada';
  end if;

  update crm.equipo
     set rol_crm = 'supervisor', supervisor_id = null
   where perfil_id = '7fa10000-0000-4000-8000-000000000001';
end;
$transiciones_analista$;

-- El trigger de inserción deriva siempre el supervisor canónico; se desactiva
-- solo para sembrar una tarea de bandeja que aísle el guard de transición.
set local session_replication_role = replica;
insert into crm.tareas (
  id, perfil_id, vendedor_id, asignado_supervisor_id,
  creado_por, tipo, titulo, vence_en
) values (
  '7fa30000-0000-4000-8000-000000000002',
  '7fa20000-0000-4000-8000-000000000001',
  current_setting('gcar.vend1')::uuid,
  '7fa10000-0000-4000-8000-000000000001',
  '7fa10000-0000-4000-8000-000000000001',
  'tarea', 'GCAR TRANSICIÓN BANDEJA SUPERVISOR', now() + interval '1 day'
);
set local session_replication_role = origin;

do $transiciones_supervisor$
declare
  v_fallo boolean := false;
  v_mensaje text;
begin
  begin
    update crm.equipo
       set rol_crm = 'vendedor',
           supervisor_id = current_setting('gcar.sup1')::uuid
     where perfil_id = '7fa10000-0000-4000-8000-000000000001';
  exception when raise_exception then
    get stacked diagnostics v_mensaje = message_text;
    v_fallo := v_mensaje like '%tareas de bandeja de supervisor%';
  end;
  if not v_fallo then
    raise exception 'GCAR-A24: el cambio Supervisor→Analista conservó una tarea de bandeja: %',
      coalesce(v_mensaje, 'sin error');
  end if;

  delete from crm.tareas
  where id = '7fa30000-0000-4000-8000-000000000002';

  update crm.equipo
     set rol_crm = 'vendedor',
         supervisor_id = current_setting('gcar.sup1')::uuid
   where perfil_id = '7fa10000-0000-4000-8000-000000000001';
  if private.rol_crm('7fa10000-0000-4000-8000-000000000001')
       is distinct from 'vendedor' then
    raise exception 'GCAR-A25: la transición limpia Supervisor→Analista fue rechazada';
  end if;
end;
$transiciones_supervisor$;

-- Fallback histórico: un cliente con `asesor_perfil_id` nulo sigue al creador
-- dentro del mismo árbol; no se vuelve global ni desaparece de su cartera.
update public.perfiles
   set asesor_perfil_id = null,
       creado_por = current_setting('gcar.vend1')::uuid
 where id = current_setting('gcar.cliente')::uuid;

select set_config('request.jwt.claim.sub', current_setting('gcar.vend1'), true);
set local role authenticated;
do $fallback_analista$
begin
  if not exists (
    select 1 from crm.clientes_basicos_fn()
    where id = current_setting('gcar.cliente')::uuid
  ) then
    raise exception 'GCAR-A13: el creador perdió su cliente aún sin analista';
  end if;
end;
$fallback_analista$;
reset role;

select set_config('request.jwt.claim.sub', current_setting('gcar.sup1'), true);
set local role authenticated;
do $fallback_supervisor$
begin
  if not exists (
    select 1 from crm.clientes_basicos_fn()
    where id = current_setting('gcar.cliente')::uuid
  ) then
    raise exception 'GCAR-A14: Supervisor perdió el cliente sin analista creado por su equipo';
  end if;
end;
$fallback_supervisor$;
reset role;

select set_config('request.jwt.claim.sub', current_setting('gcar.vend3'), true);
set local role authenticated;
do $fallback_ajeno$
begin
  if exists (
    select 1 from crm.clientes_basicos_fn()
    where id = current_setting('gcar.cliente')::uuid
  ) then
    raise exception 'GCAR-A15: el fallback filtró el cliente hacia otro árbol';
  end if;
end;
$fallback_ajeno$;
reset role;

-- Anon ni siquiera tiene EXECUTE sobre la nueva frontera.
select set_config('request.jwt.claim.sub', '', true);
set local role anon;
do $anon$
declare
  v_aceptada boolean := false;
begin
  begin
    perform * from crm.cliente_detalle_fn(current_setting('gcar.cliente')::uuid);
    v_aceptada := true;
  exception when insufficient_privilege then
    null;
  end;
  if v_aceptada then
    raise exception 'GCAR-A16: anon ejecutó cliente_detalle_fn';
  end if;
end;
$anon$;
reset role;

rollback;

select 'GESTION_CARTERA_AUTORIZACION_TX_OK' as resultado;
