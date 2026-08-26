-- F41 / Ficha 360: cierre de revocacion concurrente y separacion entre
-- lectura documental y materializacion durable del PDF.

do $preflight$
begin
  if to_regprocedure(
       'private.puede_gestionar_cuentas_cliente(uuid)'
     ) is null
     or to_regprocedure(
       'crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)'
     ) is null
     or to_regprocedure(
       'crm.actualizar_contrato_con_cuenta_pdf_v3(uuid,jsonb,jsonb,timestamptz)'
     ) is null
     or to_regprocedure(
       'private.puede_leer_contrato_pdf(uuid)'
     ) is null
     or to_regprocedure(
       'private.puede_leer_contrato_pdf_como(uuid,uuid)'
     ) is null
     or to_regprocedure(
       'crm.contrato_pdf_reservar(uuid,uuid)'
     ) is null
     or to_regprocedure(
       'crm.contrato_pdf_reclamar(uuid,uuid,integer)'
     ) is null
     or to_regprocedure(
       'crm.contrato_pdf_marcar_subido(uuid,uuid,uuid,text,bigint)'
     ) is null
     or to_regprocedure(
       'crm.contrato_pdf_marcar_error(uuid,uuid,uuid,text)'
     ) is null
     or to_regprocedure(
       'crm.contrato_pdf_finalizar(uuid,uuid,uuid)'
     ) is null
     or to_regprocedure('public.crear_contrato(jsonb,jsonb)') is null
     or to_regprocedure(
       'public.actualizar_contrato(uuid,jsonb,jsonb)'
     ) is null
     or to_regprocedure(
       'public.cerrar_contrato(uuid,text,uuid)'
     ) is null
     or to_regprocedure(
       'public._sync_contrato_titulares(uuid,jsonb)'
     ) is null
     or to_regclass('public.contrato_titulares') is null
     or to_regclass('public.cronograma_pagos') is null
     or to_regprocedure(
       'private.proteger_cronograma_documental()'
     ) is null
     or to_regprocedure(
       'private.bloquear_contratos_hijo_documental(uuid,uuid)'
     ) is null
     or to_regprocedure(
       'private.bloquear_fila_contrato_pdf(uuid)'
     ) is null
     or to_regprocedure(
       'private.bloquear_cronograma_pago_f41(uuid)'
     ) is not null
     or to_regprocedure(
       'private.bloquear_actor_cobro_directo_f41()'
     ) is not null
     or to_regprocedure(
       'private.bloquear_cronograma_cobro_statement_f41()'
     ) is not null
     or exists (
       select 1
       from pg_catalog.pg_trigger trigger
       where trigger.tgrelid = 'public.cronograma_pagos'::regclass
         and trigger.tgname =
           'trg_cronograma_pagos_00_cobro_mutex_f41'
         and not trigger.tgisinternal
     )
     or (
       select count(*)
       from pg_catalog.pg_policy policy
       where policy.polrelid = 'public.cronograma_pagos'::regclass
         and policy.polcmd = 'w'
         and policy.polpermissive
     ) <> 1
     or not exists (
       select 1
       from pg_catalog.pg_policy policy
       where policy.polrelid = 'public.cronograma_pagos'::regclass
         and policy.polname = 'cronograma_admin_actualiza'
         and policy.polcmd = 'w'
         and policy.polpermissive
     )
     or not exists (
       select 1
       from pg_catalog.pg_trigger trigger
       where trigger.tgrelid = 'public.cronograma_pagos'::regclass
         and trigger.tgname =
           'trg_cronograma_pagos_00_documental_congelado'
         and not trigger.tgisinternal
         and trigger.tgfoid =
           'private.proteger_cronograma_documental()'::regprocedure
     )
     or to_regprocedure(
       'crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)'
     ) is null
     or to_regprocedure(
       'crm.actualizar_contrato_con_cuenta(uuid,jsonb,jsonb)'
     ) is null
     or to_regprocedure(
       'public.actualizar_numero_contrato(uuid,text,text,text)'
     ) is null
     or to_regprocedure(
       'crm.actualizar_numero_contrato_pdf_v3(uuid,text,text,text)'
     ) is null
     or to_regprocedure(
       'crm.asignar_rol_usuario_fn(uuid,text,timestamptz,uuid)'
     ) is null
     or to_regprocedure(
       'crm.actualizar_jerarquia_usuario_fn(uuid,uuid,timestamptz,uuid)'
     ) is null
     or to_regprocedure(
       'crm.fijar_membresia_activa_fn(uuid,boolean,uuid,timestamptz,uuid)'
     ) is null
     or to_regprocedure(
       'crm.registrar_vendedor_usuario_fn(uuid,text,text,text,text,text,text,text,uuid,uuid)'
     ) is null
     or to_regprocedure(
       'crm.contrato_eliminacion_preparar(uuid,uuid)'
     ) is null
     or to_regprocedure(
       'crm.contrato_eliminacion_finalizar(uuid,uuid,uuid)'
     ) is null
     or to_regprocedure(
       'private.trg_restaurar_operacion_antes_borrar_contrato()'
     ) is null
     or not exists (
       select 1
       from pg_catalog.pg_trigger trigger
       where trigger.tgrelid = 'public.contratos'::regclass
         and trigger.tgname = 'trg_contratos_05_restaurar_operacion'
         and not trigger.tgisinternal
         and trigger.tgfoid =
           'private.trg_restaurar_operacion_antes_borrar_contrato()'::regprocedure
     )
     or to_regprocedure(
       'private.crear_contrato_f41_impl(jsonb,jsonb)'
     ) is not null
     or to_regprocedure(
       'private.actualizar_contrato_f41_impl(uuid,jsonb,jsonb)'
     ) is not null
     or to_regprocedure(
       'private.cerrar_contrato_f41_impl(uuid,text,uuid)'
     ) is not null
     or to_regprocedure(
       'private.crear_contrato_con_cuenta_f41_impl(jsonb,jsonb,jsonb)'
     ) is not null
     or to_regprocedure(
       'private.actualizar_contrato_con_cuenta_f41_impl(uuid,jsonb,jsonb)'
     ) is not null
     or to_regprocedure(
       'private.actualizar_numero_contrato_f41_impl(uuid,text,text,text)'
     ) is not null
     or to_regprocedure(
       'private.asignar_rol_usuario_f41_impl(uuid,text,timestamptz,uuid)'
     ) is not null
     or to_regprocedure(
       'private.actualizar_jerarquia_usuario_f41_impl(uuid,uuid,timestamptz,uuid)'
     ) is not null
     or to_regprocedure(
       'private.fijar_membresia_activa_f41_impl(uuid,boolean,uuid,timestamptz,uuid)'
     ) is not null
     or to_regprocedure(
       'private.registrar_vendedor_usuario_f41_impl(uuid,text,text,text,text,text,text,text,uuid,uuid)'
     ) is not null
     or to_regprocedure(
       'private.contrato_eliminacion_preparar_f41_impl(uuid,uuid)'
     ) is not null
     or to_regprocedure(
       'private.contrato_pdf_reservar_f41_impl(uuid,uuid)'
     ) is not null
     or to_regprocedure(
       'private.contrato_pdf_reclamar_f41_impl(uuid,uuid,integer)'
     ) is not null
     or to_regprocedure(
       'private.contrato_pdf_marcar_subido_f41_impl(uuid,uuid,uuid,text,bigint)'
     ) is not null
     or to_regprocedure(
       'private.contrato_pdf_marcar_error_f41_impl(uuid,uuid,uuid,text)'
     ) is not null
     or to_regprocedure(
       'private.contrato_pdf_finalizar_f41_impl(uuid,uuid,uuid)'
     ) is not null then
    raise exception
      'PREFLIGHT F41: falta la superficie contractual/PDF esperada';
  end if;
end;
$preflight$;

create temporary table f41_cronograma_trigger_snapshot as
select
  p.oid as oid_original,
  p.proowner as owner_original,
  p.proacl as acl_original,
  p.prosecdef as security_definer_original,
  p.provolatile as volatilidad_original,
  p.proconfig as config_original
from pg_catalog.pg_proc p
where p.oid = 'private.proteger_cronograma_documental()'::regprocedure;

create temporary table f41_contrato_pdf_lock_snapshot as
select
  p.oid as oid_original,
  p.proowner as owner_original,
  p.proacl as acl_original,
  p.prosecdef as security_definer_original,
  p.provolatile as volatilidad_original,
  p.proconfig as config_original
from pg_catalog.pg_proc p
where p.oid = 'private.bloquear_fila_contrato_pdf(uuid)'::regprocedure;

-- Toda escritura contractual autenticada debe pasar por los RPC guarded. Las
-- policies historicas de Admin no bastan: con privilegio de tabla, PostgREST
-- permitia eludir las cerraduras, la reautorizacion y la auditoria de F41.
-- service_role conserva DML para Edge Functions y finalizadores autorizados.
revoke insert, update, delete, truncate on table public.contratos
  from public, anon, authenticated;
revoke insert, update, delete, truncate on table public.contrato_titulares
  from public, anon, authenticated;
revoke insert, update, delete, truncate on table public.cronograma_pagos
  from public, anon, authenticated;
grant update (estado, fecha_pago_real, monto_pagado, registrado_por)
  on table public.cronograma_pagos to authenticated;
revoke all on function public._sync_contrato_titulares(uuid,jsonb)
  from public, anon, authenticated;
grant execute on function public._sync_contrato_titulares(uuid,jsonb)
  to service_role;

-- PostgREST conserva el UPDATE operativo de Pagos. El mutex no vive dentro de
-- RLS: una qual puede reevaluarse por fila y durante EvalPlanQual. Un trigger
-- BEFORE STATEMENT lo toma una sola vez, antes de cualquier lock de cuota.
create or replace function private.bloquear_actor_cobro_directo_f41()
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_actor_id uuid := (select auth.uid());
begin
  if pg_catalog.pg_trigger_depth() <> 1
     or v_actor_id is null
     or not coalesce(public.es_gestor_cartera(), false) then
    raise insufficient_privilege using
      message = 'La autoridad para registrar cobros ya no esta vigente';
  end if;

  perform pg_catalog.pg_advisory_xact_lock_shared(
    pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'public.cronograma_pagos.cobros_f41',
      0
    )
  );

  perform 1
  from public.perfiles actor
  where actor.id = v_actor_id
    and actor.activo is true
  for share;
  if not found then
    raise insufficient_privilege using
      message = 'La autoridad para registrar cobros ya no esta vigente';
  end if;

  if not coalesce(public.es_gestor_cartera(), false) then
    raise insufficient_privilege using
      message = 'La autoridad para registrar cobros ya no esta vigente';
  end if;
end;
$function$;

comment on function private.bloquear_actor_cobro_directo_f41() is
  'Solo desde el trigger de sentencia: congela jerarquia, mutex de cobros y perfil del actor REST antes de tocar cuotas.';

revoke all on function private.bloquear_actor_cobro_directo_f41()
  from public, anon, authenticated, service_role;
grant execute on function private.bloquear_actor_cobro_directo_f41()
  to authenticated;

create or replace function private.bloquear_cronograma_cobro_statement_f41()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $function$
begin
  if current_user = 'authenticated' then
    perform private.bloquear_actor_cobro_directo_f41();
  elsif current_user = 'service_role' then
    perform pg_catalog.pg_advisory_xact_lock_shared(
      pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0)
    );
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(
        'public.cronograma_pagos.cobros_f41',
        0
      )
    );
  end if;
  return null;
end;
$function$;

comment on function private.bloquear_cronograma_cobro_statement_f41() is
  'BEFORE STATEMENT para UPDATE operativo: toma jerarquia y mutex EXCLUSIVE antes de cualquier tuple lock; RLS permanece libre de efectos laterales.';

revoke all on function private.bloquear_cronograma_cobro_statement_f41()
  from public, anon, authenticated, service_role;

create trigger trg_cronograma_pagos_00_cobro_mutex_f41
before update of estado, fecha_pago_real, monto_pagado, registrado_por
on public.cronograma_pagos
for each statement
execute function private.bloquear_cronograma_cobro_statement_f41();

alter policy cronograma_admin_actualiza on public.cronograma_pagos
using (public.es_gestor_cartera())
with check (public.es_gestor_cartera());

-- Los sellos idempotentes del notificador no cambian cobro, términos ni la
-- elegibilidad del hard-delete. Los cobros operativos ya llegan protegidos por
-- el trigger de sentencia y tampoco vuelven a pedir el padre desde la fila hija.
-- Cualquier cambio documental conserva la ruta parent-lock del trigger.
create or replace function private.proteger_cronograma_documental()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_anterior uuid := case
    when tg_op in ('UPDATE', 'DELETE') then old.contrato_id
  end;
  v_nuevo uuid := case
    when tg_op in ('INSERT', 'UPDATE') then new.contrato_id
  end;
  v_cambio_documental boolean := true;
begin
  if tg_op = 'DELETE'
     and current_setting(
       'crm.contrato_pdf_eliminacion_autorizada',
       true
     ) = old.contrato_id::text then
    return old;
  end if;

  if tg_op = 'UPDATE'
     and (
       pg_catalog.to_jsonb(new)
         - array[
           'notif_pago_enviada_en',
           'recordatorio_3d_enviado_en'
         ]::text[]
     ) is not distinct from (
       pg_catalog.to_jsonb(old)
         - array[
           'notif_pago_enviada_en',
           'recordatorio_3d_enviado_en'
         ]::text[]
     ) then
    return new;
  end if;

  if tg_op = 'UPDATE' then
    v_cambio_documental := row(
      new.id, new.contrato_id, new.numero_cuota, new.fecha_programada,
      new.monto_programado, new.tipo
    ) is distinct from row(
      old.id, old.contrato_id, old.numero_cuota, old.fecha_programada,
      old.monto_programado, old.tipo
    );
  end if;
  if not v_cambio_documental then
    if private.contrato_en_eliminacion(v_anterior)
       and not private.mutacion_documental_autorizada(v_anterior) then
      raise exception 'El contrato está en proceso de eliminación'
        using errcode = '55000';
    end if;
    return new;
  end if;

  perform private.bloquear_contratos_hijo_documental(v_anterior, v_nuevo);
  if (
    v_anterior is not null
    and private.contrato_en_eliminacion(v_anterior)
    and not private.mutacion_documental_autorizada(v_anterior)
  ) or (
    v_nuevo is not null
    and private.contrato_en_eliminacion(v_nuevo)
    and not private.mutacion_documental_autorizada(v_nuevo)
  ) then
    raise exception 'El contrato está en proceso de eliminación'
      using errcode = '55000';
  end if;

  if (
    v_anterior is not null
    and private.contrato_documental_congelado(v_anterior)
    and not private.mutacion_documental_autorizada(v_anterior)
  ) or (
    v_nuevo is not null
    and private.contrato_documental_congelado(v_nuevo)
    and not private.mutacion_documental_autorizada(v_nuevo)
  ) then
    raise exception
      'El cronograma contractual está congelado por su PDF legal'
      using errcode = '55000';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$function$;

do $mutex_cobros_bloqueo_pdf$
declare
  v_definicion text;
  v_marcador text := E'  perform 1\n  from public.contratos';
  v_reemplazo text := E'  perform pg_catalog.pg_advisory_xact_lock_shared(\n'
    || E'    pg_catalog.hashtextextended(\n'
    || E'      ''public.cronograma_pagos.cobros_f41'',\n'
    || E'      0\n'
    || E'    )\n'
    || E'  );\n'
    || v_marcador;
begin
  select pg_catalog.pg_get_functiondef(
    'private.bloquear_fila_contrato_pdf(uuid)'::regprocedure
  ) into v_definicion;
  if v_definicion ilike '%public.cronograma_pagos.cobros_f41%'
     or (
       pg_catalog.length(v_definicion)
         - pg_catalog.length(
           pg_catalog.replace(v_definicion, v_marcador, '')
         )
     ) / pg_catalog.length(v_marcador) <> 1 then
    raise exception
      'PREFLIGHT F41: bloqueo PDF no es la familia canonica esperada';
  end if;
  execute pg_catalog.replace(v_definicion, v_marcador, v_reemplazo);
end;
$mutex_cobros_bloqueo_pdf$;

-- El finalizador puede disparar la restauracion de una renovacion: ese trigger
-- legacy toca primero cuotas del contrato origen y luego su fila padre. Se lo
-- separa de todo writer parent-first con EXCLUSIVE antes del contrato nuevo.
do $mutex_cobros_finalizar_delete$
declare
  v_definicion text;
  v_marcador text :=
    E'  perform private.bloquear_fila_contrato_pdf(p_contrato_id);';
  v_reemplazo text :=
    E'  perform pg_catalog.pg_advisory_xact_lock_shared(\n'
    || E'    pg_catalog.hashtextextended(''crm.equipo.usuarios_jerarquia'', 0)\n'
    || E'  );\n'
    || E'  perform pg_catalog.pg_advisory_xact_lock(\n'
    || E'    pg_catalog.hashtextextended(\n'
    || E'      ''public.cronograma_pagos.cobros_f41'',\n'
    || E'      0\n'
    || E'    )\n'
    || E'  );\n'
    || v_marcador;
begin
  select pg_catalog.pg_get_functiondef(
    'crm.contrato_eliminacion_finalizar(uuid,uuid,uuid)'::regprocedure
  ) into v_definicion;
  if v_definicion ilike '%public.cronograma_pagos.cobros_f41%'
     or (
       pg_catalog.length(v_definicion)
         - pg_catalog.length(
           pg_catalog.replace(v_definicion, v_marcador, '')
         )
     ) / pg_catalog.length(v_marcador) <> 1 then
    raise exception
      'PREFLIGHT F41: finalizador delete no es la familia canonica esperada';
  end if;
  execute pg_catalog.replace(v_definicion, v_marcador, v_reemplazo);
end;
$mutex_cobros_finalizar_delete$;

-- La autoridad mutable vive en perfiles.asesor_perfil_id. Este helper toma
-- el lock de esa fila antes de cualquier lock de contrato/cuenta/PDF, espera
-- una reasignacion ya iniciada y revalida el alcance una vez adquirido. El
-- FOR SHARE se conserva hasta COMMIT y hace esperar cualquier UPDATE del
-- perfil, incluida una reasignacion o baja concurrente.
create or replace function private.bloquear_cliente_para_mutacion(
  p_cliente_id uuid
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_actor_id uuid;
  v_cliente_id uuid;
begin
  v_actor_id := (select auth.uid());
  if v_actor_id is null or p_cliente_id is null then
    raise insufficient_privilege using
      message = 'Cliente no encontrado o fuera de tu cartera';
  end if;

  -- El precheck evita que un actor sin alcance use UUID arbitrarios para
  -- mantener bloqueadas filas de clientes legitimos.
  if not private.puede_gestionar_cuentas_cliente(p_cliente_id) then
    raise insufficient_privilege using
      message = 'Cliente no encontrado o fuera de tu cartera';
  end if;

  -- Los escritores de jerarquia/rol/baja toman esta misma llave en exclusivo.
  -- La jerarquia queda congelada hasta COMMIT; el mutex SHARED posterior deja
  -- concurrir writers parent-first y los separa del cobro directo EXCLUSIVE.
  perform pg_catalog.pg_advisory_xact_lock_shared(
    pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0)
  );
  perform pg_catalog.pg_advisory_xact_lock_shared(
    pg_catalog.hashtextextended(
      'public.cronograma_pagos.cobros_f41',
      0
    )
  );

  -- El alcance tambien depende de rol/activo del perfil Portal. Esa fila se
  -- congela aunque un cambio directo por RLS no use la llave de crm.equipo.
  perform 1
  from public.perfiles actor
  where actor.id = v_actor_id
    and actor.activo is true
  for share;
  if not found then
    raise insufficient_privilege using
      message = 'Cliente no encontrado o fuera de tu cartera';
  end if;

  select p.id
    into v_cliente_id
  from public.perfiles p
  where p.id = p_cliente_id
    and p.rol = 'cliente'
  for share;

  if not found
     or not private.puede_gestionar_cuentas_cliente(v_cliente_id) then
    raise insufficient_privilege using
      message = 'Cliente no encontrado o fuera de tu cartera';
  end if;
end;
$function$;

comment on function private.bloquear_cliente_para_mutacion(uuid) is
  'Serializa autoridad y asignacion vigentes antes de mutaciones contractuales. Jerarquia y mutex de cobros compartidos preceden perfiles, contrato, cuenta o PDF.';

revoke all on function private.bloquear_cliente_para_mutacion(uuid)
  from public, anon, authenticated, service_role;

-- Las RPC publicas de correccion conservan una excepcion administrativa para
-- contratos historicos de clientes inactivos/no asignados. Esta guardia toma
-- los mismos locks sin convertir el helper bancario estricto en una nueva
-- regla de negocio; el cuerpo canonico sigue decidiendo autor, ventana y rol.
create or replace function private.bloquear_contrato_para_correccion_f41(
  p_contrato_id uuid,
  p_modo text
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_actor_id uuid := (select auth.uid());
  v_cliente_id uuid;
  v_cliente_bloqueado_id uuid;
  v_rol_crm text;
  v_autorizado boolean;
begin
  if v_actor_id is null
     or p_modo not in ('terminos', 'numero', 'cierre') then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu autoridad';
  end if;

  select c.cliente_id into v_cliente_id
  from public.contratos c
  where c.id = p_contrato_id;
  if not found then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu autoridad';
  end if;

  v_rol_crm := private.rol_crm(v_actor_id);
  v_autorizado := case p_modo
    when 'cierre' then
      public.es_admin()
      and not private.membresia_crm_revocada()
    when 'numero' then
      public.es_gestor_cartera()
      and not private.membresia_crm_revocada()
    when 'terminos' then
      (
        (
          public.es_gestor_cartera()
          or coalesce(v_rol_crm = 'gerencia', false)
        )
        and not private.membresia_crm_revocada()
      )
      or private.puede_gestionar_cuentas_cliente(v_cliente_id)
  end;
  if not coalesce(v_autorizado, false) then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu autoridad';
  end if;

  perform pg_catalog.pg_advisory_xact_lock_shared(
    pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0)
  );
  perform pg_catalog.pg_advisory_xact_lock_shared(
    pg_catalog.hashtextextended(
      'public.cronograma_pagos.cobros_f41',
      0
    )
  );

  perform 1
  from public.perfiles actor
  where actor.id = v_actor_id
    and actor.activo is true
  for share;
  if not found then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu autoridad';
  end if;

  perform 1
  from public.perfiles cliente
  where cliente.id = v_cliente_id
  for share;
  if not found then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu autoridad';
  end if;

  select c.cliente_id into v_cliente_bloqueado_id
  from public.contratos c
  where c.id = p_contrato_id
  for update;
  if not found or v_cliente_bloqueado_id is distinct from v_cliente_id then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu autoridad';
  end if;

  v_rol_crm := private.rol_crm(v_actor_id);
  v_autorizado := case p_modo
    when 'cierre' then
      public.es_admin()
      and not private.membresia_crm_revocada()
    when 'numero' then
      public.es_gestor_cartera()
      and not private.membresia_crm_revocada()
    when 'terminos' then
      (
        (
          public.es_gestor_cartera()
          or coalesce(v_rol_crm = 'gerencia', false)
        )
        and not private.membresia_crm_revocada()
      )
      or private.puede_gestionar_cuentas_cliente(v_cliente_bloqueado_id)
  end;
  if not coalesce(v_autorizado, false) then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu autoridad';
  end if;
end;
$function$;

comment on function private.bloquear_contrato_para_correccion_f41(uuid,text) is
  'Serializa correcciones y cierre canonico con mutex de cobros antes de contrato, sin exigir que un cliente historico siga activo/asignado.';

revoke all on function private.bloquear_contrato_para_correccion_f41(uuid,text)
  from public, anon, authenticated, service_role;

-- Los cuerpos canonicos se clonan a funciones privadas y las firmas originales
-- se reemplazan in-place. CREATE OR REPLACE conserva el OID original: cualquier
-- funcion SQL ya enlazada a ese OID atraviesa tambien la nueva guardia, en vez
-- de quedar apuntando a una implementacion movida que eluda la envoltura.
create temporary table f41_writer_oids (
  firma text primary key,
  oid_original oid not null
);

insert into f41_writer_oids (firma, oid_original) values
  (
    'public.crear_contrato(jsonb,jsonb)',
    'public.crear_contrato(jsonb,jsonb)'::regprocedure::oid
  ),
  (
    'public.actualizar_contrato(uuid,jsonb,jsonb)',
    'public.actualizar_contrato(uuid,jsonb,jsonb)'::regprocedure::oid
  ),
  (
    'public.cerrar_contrato(uuid,text,uuid)',
    'public.cerrar_contrato(uuid,text,uuid)'::regprocedure::oid
  ),
  (
    'crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)',
    'crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)'::regprocedure::oid
  ),
  (
    'crm.actualizar_contrato_con_cuenta(uuid,jsonb,jsonb)',
    'crm.actualizar_contrato_con_cuenta(uuid,jsonb,jsonb)'::regprocedure::oid
  ),
  (
    'public.actualizar_numero_contrato(uuid,text,text,text)',
    'public.actualizar_numero_contrato(uuid,text,text,text)'::regprocedure::oid
  ),
  (
    'crm.actualizar_numero_contrato_pdf_v3(uuid,text,text,text)',
    'crm.actualizar_numero_contrato_pdf_v3(uuid,text,text,text)'::regprocedure::oid
  ),
  (
    'crm.asignar_rol_usuario_fn(uuid,text,timestamptz,uuid)',
    'crm.asignar_rol_usuario_fn(uuid,text,timestamptz,uuid)'::regprocedure::oid
  ),
  (
    'crm.actualizar_jerarquia_usuario_fn(uuid,uuid,timestamptz,uuid)',
    'crm.actualizar_jerarquia_usuario_fn(uuid,uuid,timestamptz,uuid)'::regprocedure::oid
  ),
  (
    'crm.fijar_membresia_activa_fn(uuid,boolean,uuid,timestamptz,uuid)',
    'crm.fijar_membresia_activa_fn(uuid,boolean,uuid,timestamptz,uuid)'::regprocedure::oid
  ),
  (
    'crm.registrar_vendedor_usuario_fn(uuid,text,text,text,text,text,text,text,uuid,uuid)',
    'crm.registrar_vendedor_usuario_fn(uuid,text,text,text,text,text,text,text,uuid,uuid)'::regprocedure::oid
  ),
  (
    'crm.contrato_eliminacion_preparar(uuid,uuid)',
    'crm.contrato_eliminacion_preparar(uuid,uuid)'::regprocedure::oid
  ),
  (
    'crm.contrato_eliminacion_finalizar(uuid,uuid,uuid)',
    'crm.contrato_eliminacion_finalizar(uuid,uuid,uuid)'::regprocedure::oid
  );

create temporary table f41_guarded_snapshots as
select
  firmas.firma,
  p.oid as oid_original,
  p.proowner as owner_original,
  p.proacl as acl_original
from unnest(array[
  'public.cerrar_contrato(uuid,text,uuid)',
  'public.actualizar_numero_contrato(uuid,text,text,text)',
  'crm.actualizar_numero_contrato_pdf_v3(uuid,text,text,text)',
  'crm.asignar_rol_usuario_fn(uuid,text,timestamptz,uuid)',
  'crm.actualizar_jerarquia_usuario_fn(uuid,uuid,timestamptz,uuid)',
  'crm.fijar_membresia_activa_fn(uuid,boolean,uuid,timestamptz,uuid)',
  'crm.registrar_vendedor_usuario_fn(uuid,text,text,text,text,text,text,text,uuid,uuid)',
  'crm.contrato_eliminacion_preparar(uuid,uuid)',
  'crm.contrato_eliminacion_finalizar(uuid,uuid,uuid)'
]::text[]) as firmas(firma)
join pg_catalog.pg_proc p
  on p.oid = firmas.firma::regprocedure;

alter table f41_guarded_snapshots add primary key (firma);

do $clonar_escritores$
declare
  v_definicion text;
  v_clon text;
  v_cabecera text;
  v_propietario name;
begin
  select pg_catalog.pg_get_functiondef(
    'public.crear_contrato(jsonb,jsonb)'::regprocedure
  ) into v_definicion;
  if v_definicion not ilike '%tiene_capacidad_contrato_atomico%'
     or v_definicion not ilike '%puede_gestionar_cuentas_cliente%' then
    raise exception 'PREFLIGHT F41: crear_contrato no es el cuerpo canonico esperado';
  end if;
  v_cabecera := 'FUNCTION public.crear_contrato(';
  if (
    pg_catalog.length(v_definicion)
      - pg_catalog.length(pg_catalog.replace(v_definicion, v_cabecera, ''))
  ) / pg_catalog.length(v_cabecera) <> 1 then
    raise exception 'PREFLIGHT F41: cabecera ambigua en crear_contrato';
  end if;
  v_clon := pg_catalog.replace(
    v_definicion,
    v_cabecera,
    'FUNCTION private.crear_contrato_f41_impl('
  );
  execute v_clon;
  select r.rolname into strict v_propietario
  from pg_catalog.pg_proc p
  join pg_catalog.pg_roles r on r.oid = p.proowner
  where p.oid = 'public.crear_contrato(jsonb,jsonb)'::regprocedure;
  execute pg_catalog.format(
    'alter function private.crear_contrato_f41_impl(jsonb,jsonb) owner to %I',
    v_propietario
  );

  select pg_catalog.pg_get_functiondef(
    'public.actualizar_contrato(uuid,jsonb,jsonb)'::regprocedure
  ) into v_definicion;
  if v_definicion not ilike '%tiene_capacidad_contrato_atomico%'
     or v_definicion not ilike '%puede_gestionar_cuentas_cliente%' then
    raise exception
      'PREFLIGHT F41: actualizar_contrato no es el cuerpo canonico esperado';
  end if;
  v_cabecera := 'FUNCTION public.actualizar_contrato(';
  if (
    pg_catalog.length(v_definicion)
      - pg_catalog.length(pg_catalog.replace(v_definicion, v_cabecera, ''))
  ) / pg_catalog.length(v_cabecera) <> 1 then
    raise exception 'PREFLIGHT F41: cabecera ambigua en actualizar_contrato';
  end if;
  v_clon := pg_catalog.replace(
    v_definicion,
    v_cabecera,
    'FUNCTION private.actualizar_contrato_f41_impl('
  );
  execute v_clon;
  select r.rolname into strict v_propietario
  from pg_catalog.pg_proc p
  join pg_catalog.pg_roles r on r.oid = p.proowner
  where p.oid =
    'public.actualizar_contrato(uuid,jsonb,jsonb)'::regprocedure;
  execute pg_catalog.format(
    'alter function private.actualizar_contrato_f41_impl(uuid,jsonb,jsonb) owner to %I',
    v_propietario
  );

  select pg_catalog.pg_get_functiondef(
    'crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)'::regprocedure
  ) into v_definicion;
  if v_definicion not ilike '%pg_advisory_xact_lock%'
     or v_definicion not ilike '%public.crear_contrato%' then
    raise exception
      'PREFLIGHT F41: crear_contrato_con_cuenta no es el cuerpo canonico esperado';
  end if;
  v_cabecera := 'FUNCTION crm.crear_contrato_con_cuenta(';
  if (
    pg_catalog.length(v_definicion)
      - pg_catalog.length(pg_catalog.replace(v_definicion, v_cabecera, ''))
  ) / pg_catalog.length(v_cabecera) <> 1 then
    raise exception
      'PREFLIGHT F41: cabecera ambigua en crear_contrato_con_cuenta';
  end if;
  v_clon := pg_catalog.replace(
    v_definicion,
    v_cabecera,
    'FUNCTION private.crear_contrato_con_cuenta_f41_impl('
  );
  execute v_clon;
  select r.rolname into strict v_propietario
  from pg_catalog.pg_proc p
  join pg_catalog.pg_roles r on r.oid = p.proowner
  where p.oid =
    'crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)'::regprocedure;
  execute pg_catalog.format(
    'alter function private.crear_contrato_con_cuenta_f41_impl(jsonb,jsonb,jsonb) owner to %I',
    v_propietario
  );

  select pg_catalog.pg_get_functiondef(
    'crm.actualizar_contrato_con_cuenta(uuid,jsonb,jsonb)'::regprocedure
  ) into v_definicion;
  if v_definicion not ilike '%public.actualizar_contrato%'
     or v_definicion not ilike '%puede_gestionar_cuentas_cliente%' then
    raise exception
      'PREFLIGHT F41: actualizar_contrato_con_cuenta no es el cuerpo canonico esperado';
  end if;
  v_cabecera := 'FUNCTION crm.actualizar_contrato_con_cuenta(';
  if (
    pg_catalog.length(v_definicion)
      - pg_catalog.length(pg_catalog.replace(v_definicion, v_cabecera, ''))
  ) / pg_catalog.length(v_cabecera) <> 1 then
    raise exception
      'PREFLIGHT F41: cabecera ambigua en actualizar_contrato_con_cuenta';
  end if;
  v_clon := pg_catalog.replace(
    v_definicion,
    v_cabecera,
    'FUNCTION private.actualizar_contrato_con_cuenta_f41_impl('
  );
  execute v_clon;
  select r.rolname into strict v_propietario
  from pg_catalog.pg_proc p
  join pg_catalog.pg_roles r on r.oid = p.proowner
  where p.oid =
    'crm.actualizar_contrato_con_cuenta(uuid,jsonb,jsonb)'::regprocedure;
  execute pg_catalog.format(
    'alter function private.actualizar_contrato_con_cuenta_f41_impl(uuid,jsonb,jsonb) owner to %I',
    v_propietario
  );
end;
$clonar_escritores$;

-- Las firmas adicionales se clonan con el mismo patron, pero sus cuerpos
-- vigentes vienen de hitos distintos. Los marcadores abortan si una instalacion
-- no contiene exactamente la familia canonica que fue auditada.
create temporary table f41_extra_writer_specs (
  firma text primary key,
  cabecera text not null,
  cabecera_clon text not null,
  firma_clon text not null,
  marcador_uno text not null,
  marcador_dos text not null,
  marcador_tres text
);

insert into f41_extra_writer_specs values
  (
    'public.actualizar_numero_contrato(uuid,text,text,text)',
    'FUNCTION public.actualizar_numero_contrato(',
    'FUNCTION private.actualizar_numero_contrato_f41_impl(',
    'private.actualizar_numero_contrato_f41_impl(uuid,text,text,text)',
    'public.es_gestor_cartera',
    'private.membresia_crm_revocada',
    null
  ),
  (
    'public.cerrar_contrato(uuid,text,uuid)',
    'FUNCTION public.cerrar_contrato(',
    'FUNCTION private.cerrar_contrato_f41_impl(',
    'private.cerrar_contrato_f41_impl(uuid,text,uuid)',
    'es_admin()',
    'update cronograma_pagos',
    'for update'
  ),
  (
    'crm.asignar_rol_usuario_fn(uuid,text,timestamptz,uuid)',
    'FUNCTION crm.asignar_rol_usuario_fn(',
    'FUNCTION private.asignar_rol_usuario_f41_impl(',
    'private.asignar_rol_usuario_f41_impl(uuid,text,timestamptz,uuid)',
    'private.es_superadmin_portal_activo',
    'pg_advisory_xact_lock',
    '(''comercial'', ''analista'')'
  ),
  (
    'crm.actualizar_jerarquia_usuario_fn(uuid,uuid,timestamptz,uuid)',
    'FUNCTION crm.actualizar_jerarquia_usuario_fn(',
    'FUNCTION private.actualizar_jerarquia_usuario_f41_impl(',
    'private.actualizar_jerarquia_usuario_f41_impl(uuid,uuid,timestamptz,uuid)',
    'private.es_gerencia_crm_activa',
    'private.validar_supervisor_usuario_crm',
    null
  ),
  (
    'crm.fijar_membresia_activa_fn(uuid,boolean,uuid,timestamptz,uuid)',
    'FUNCTION crm.fijar_membresia_activa_fn(',
    'FUNCTION private.fijar_membresia_activa_f41_impl(',
    'private.fijar_membresia_activa_f41_impl(uuid,boolean,uuid,timestamptz,uuid)',
    'private.es_gerencia_crm_activa',
    'crm.impacto_desactivacion_usuario_fn',
    null
  ),
  (
    'crm.registrar_vendedor_usuario_fn(uuid,text,text,text,text,text,text,text,uuid,uuid)',
    'FUNCTION crm.registrar_vendedor_usuario_fn(',
    'FUNCTION private.registrar_vendedor_usuario_f41_impl(',
    'private.registrar_vendedor_usuario_f41_impl(uuid,text,text,text,text,text,text,text,uuid,uuid)',
    'private.es_gerencia_crm_activa',
    'private.validar_supervisor_usuario_crm',
    null
  ),
  (
    'crm.contrato_eliminacion_preparar(uuid,uuid)',
    'FUNCTION crm.contrato_eliminacion_preparar(',
    'FUNCTION private.contrato_eliminacion_preparar_f41_impl(',
    'private.contrato_eliminacion_preparar_f41_impl(uuid,uuid)',
    'private.bloquear_fila_contrato_pdf',
    'private.poder_eliminar_contrato_como',
    null
  );

do $clonar_escritores_extra$
declare
  r record;
  v_definicion text;
  v_clon text;
  v_propietario name;
begin
  for r in select * from f41_extra_writer_specs order by firma loop
    select pg_catalog.pg_get_functiondef(r.firma::regprocedure)
      into v_definicion;
    if v_definicion not ilike '%' || r.marcador_uno || '%'
       or v_definicion not ilike '%' || r.marcador_dos || '%'
       or (
         r.marcador_tres is not null
         and v_definicion not ilike '%' || r.marcador_tres || '%'
       ) then
      raise exception
        'PREFLIGHT F41: % no es el cuerpo canonico esperado', r.firma;
    end if;
    if (
      pg_catalog.length(v_definicion)
        - pg_catalog.length(
            pg_catalog.replace(v_definicion, r.cabecera, '')
          )
    ) / pg_catalog.length(r.cabecera) <> 1 then
      raise exception 'PREFLIGHT F41: cabecera ambigua en %', r.firma;
    end if;

    v_clon := pg_catalog.replace(
      v_definicion,
      r.cabecera,
      r.cabecera_clon
    );
    execute v_clon;

    select roles.rolname into strict v_propietario
    from pg_catalog.pg_proc p
    join pg_catalog.pg_roles roles on roles.oid = p.proowner
    where p.oid = r.firma::regprocedure;
    execute pg_catalog.format(
      'alter function %s owner to %I',
      r.firma_clon,
      v_propietario
    );
  end loop;
end;
$clonar_escritores_extra$;

revoke all on function private.crear_contrato_f41_impl(jsonb,jsonb)
  from public, anon, authenticated, service_role;
revoke all on function private.actualizar_contrato_f41_impl(uuid,jsonb,jsonb)
  from public, anon, authenticated, service_role;
revoke all on function private.cerrar_contrato_f41_impl(uuid,text,uuid)
  from public, anon, authenticated, service_role;
revoke all on function private.crear_contrato_con_cuenta_f41_impl(
  jsonb,
  jsonb,
  jsonb
) from public, anon, authenticated, service_role;
revoke all on function private.actualizar_contrato_con_cuenta_f41_impl(
  uuid,
  jsonb,
  jsonb
) from public, anon, authenticated, service_role;
revoke all on function private.actualizar_numero_contrato_f41_impl(
  uuid,
  text,
  text,
  text
) from public, anon, authenticated, service_role;
revoke all on function private.asignar_rol_usuario_f41_impl(
  uuid,
  text,
  timestamptz,
  uuid
) from public, anon, authenticated, service_role;
revoke all on function private.actualizar_jerarquia_usuario_f41_impl(
  uuid,
  uuid,
  timestamptz,
  uuid
) from public, anon, authenticated, service_role;
revoke all on function private.fijar_membresia_activa_f41_impl(
  uuid,
  boolean,
  uuid,
  timestamptz,
  uuid
) from public, anon, authenticated, service_role;
revoke all on function private.registrar_vendedor_usuario_f41_impl(
  uuid,
  text,
  text,
  text,
  text,
  text,
  text,
  text,
  uuid,
  uuid
) from public, anon, authenticated, service_role;
revoke all on function private.contrato_eliminacion_preparar_f41_impl(
  uuid,
  uuid
) from public, anon, authenticated, service_role;

-- Los administradores de roles/jerarquia/bajas usan la misma llave global en
-- exclusivo. La guardia hace un precheck barato, espera la llave, congela el
-- perfil Portal del actor y revalida su autoridad antes de cualquier efecto.
create or replace function private.bloquear_actor_mutador_equipo_f41(
  p_autoridad text
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_actor_id uuid := (select auth.uid());
  v_autorizado boolean;
begin
  if p_autoridad not in ('superadmin', 'gerencia') then
    raise exception 'Autoridad mutadora F41 invalida' using errcode = '22023';
  end if;

  v_autorizado := case p_autoridad
    when 'superadmin' then private.es_superadmin_portal_activo()
    when 'gerencia' then private.es_gerencia_crm_activa()
  end;
  if v_actor_id is null or not coalesce(v_autorizado, false) then
    raise insufficient_privilege using
      message = 'La autoridad para administrar el equipo ya no esta vigente';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0)
  );

  perform 1
  from public.perfiles actor
  where actor.id = v_actor_id
    and actor.activo is true
  for share;
  if not found then
    raise insufficient_privilege using
      message = 'La autoridad para administrar el equipo ya no esta vigente';
  end if;

  v_autorizado := case p_autoridad
    when 'superadmin' then private.es_superadmin_portal_activo()
    when 'gerencia' then private.es_gerencia_crm_activa()
  end;
  if not coalesce(v_autorizado, false) then
    raise insufficient_privilege using
      message = 'La autoridad para administrar el equipo ya no esta vigente';
  end if;
end;
$function$;

comment on function private.bloquear_actor_mutador_equipo_f41(text) is
  'Linealiza mutadores exclusivos del equipo: llave global, perfil actor FOR SHARE y reautorizacion bajo ambos locks.';

revoke all on function private.bloquear_actor_mutador_equipo_f41(text)
  from public, anon, authenticated, service_role;

create or replace function crm.asignar_rol_usuario_fn(
  p_perfil_id uuid,
  p_rol_crm text,
  p_version_equipo timestamptz,
  p_idempotencia uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
begin
  perform private.bloquear_actor_mutador_equipo_f41('superadmin');
  return private.asignar_rol_usuario_f41_impl(
    p_perfil_id,
    p_rol_crm,
    p_version_equipo,
    p_idempotencia
  );
end;
$function$;

create or replace function crm.actualizar_jerarquia_usuario_fn(
  p_perfil_id uuid,
  p_supervisor_id uuid,
  p_version_equipo timestamptz,
  p_idempotencia uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
begin
  perform private.bloquear_actor_mutador_equipo_f41('gerencia');
  return private.actualizar_jerarquia_usuario_f41_impl(
    p_perfil_id,
    p_supervisor_id,
    p_version_equipo,
    p_idempotencia
  );
end;
$function$;

create or replace function crm.fijar_membresia_activa_fn(
  p_perfil_id uuid,
  p_activo boolean,
  p_reemplazo_id uuid,
  p_version_equipo timestamptz,
  p_idempotencia uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
begin
  perform private.bloquear_actor_mutador_equipo_f41('gerencia');
  return private.fijar_membresia_activa_f41_impl(
    p_perfil_id,
    p_activo,
    p_reemplazo_id,
    p_version_equipo,
    p_idempotencia
  );
end;
$function$;

create or replace function crm.registrar_vendedor_usuario_fn(
  p_perfil_id uuid,
  p_correo text,
  p_nombre_completo text,
  p_tipo_documento text,
  p_documento text,
  p_telefono text,
  p_whatsapp text,
  p_cargo text,
  p_supervisor_id uuid,
  p_idempotencia uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
begin
  perform private.bloquear_actor_mutador_equipo_f41('gerencia');
  return private.registrar_vendedor_usuario_f41_impl(
    p_perfil_id,
    p_correo,
    p_nombre_completo,
    p_tipo_documento,
    p_documento,
    p_telefono,
    p_whatsapp,
    p_cargo,
    p_supervisor_id,
    p_idempotencia
  );
end;
$function$;

-- Hard-delete pertenece al Portal, no al rol CRM. La preparacion es el punto
-- de linealizacion previo al borrado Storage. Toma el mismo orden global que el
-- finalizador (jerarquia -> cobros EXCLUSIVE -> actor -> contrato), de modo que
-- incluso un consumidor service_role que encadene preparar+finalizar dentro de
-- una sola transaccion no intente elevar un mutex SHARED mientras conserva el
-- perfil/contrato. El flujo Edge normal sigue confirmando preparar antes de IO.
create or replace function private.bloquear_actor_eliminacion_contrato_f41(
  p_actor_id uuid
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_sub_anterior text := current_setting('request.jwt.claim.sub', true);
  v_actor_valido boolean;
begin
  if p_actor_id is null then
    raise insufficient_privilege using
      message = 'Solo Admin o Superadmin puede eliminar contratos';
  end if;

  -- Precheck MVCC sin bloqueo: un UUID inválido/no administrativo no debe
  -- adquirir el mutex global de cobros. La misma condición se revalida con
  -- un bloqueo compartido de fila después de los mutex para cerrar el TOCTOU.
  select exists (
    select 1
    from public.perfiles actor
    where actor.id = p_actor_id
      and actor.activo is true
      and actor.rol in ('admin', 'superadmin')
  ) into v_actor_valido;
  if not coalesce(v_actor_valido, false) then
    raise insufficient_privilege using
      message = 'Solo Admin o Superadmin puede eliminar contratos';
  end if;

  perform pg_catalog.pg_advisory_xact_lock_shared(
    pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'public.cronograma_pagos.cobros_f41',
      0
    )
  );

  perform set_config('request.jwt.claim.sub', p_actor_id::text, true);
  perform 1
  from public.perfiles actor
  where actor.id = p_actor_id
    and actor.activo is true
    and actor.rol in ('admin', 'superadmin')
  for share;
  v_actor_valido := found;
  perform set_config(
    'request.jwt.claim.sub',
    coalesce(v_sub_anterior, ''),
    true
  );
  if not coalesce(v_actor_valido, false) then
    raise insufficient_privilege using
      message = 'Solo Admin o Superadmin puede eliminar contratos';
  end if;
exception when others then
  perform set_config(
    'request.jwt.claim.sub',
    coalesce(v_sub_anterior, ''),
    true
  );
  raise;
end;
$function$;

comment on function private.bloquear_actor_eliminacion_contrato_f41(uuid) is
  'Linealiza hard-delete con jerarquia SHARED y cobros EXCLUSIVE antes del perfil Portal y contrato. La preparacion confirmada autoriza terminar el borrado externo.';

revoke all on function private.bloquear_actor_eliminacion_contrato_f41(uuid)
  from public, anon, authenticated, service_role;

create or replace function crm.contrato_eliminacion_preparar(
  p_contrato_id uuid,
  p_actor_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_resultado jsonb;
  v_token uuid;
begin
  perform private.bloquear_actor_eliminacion_contrato_f41(p_actor_id);
  v_resultado := private.contrato_eliminacion_preparar_f41_impl(
    p_contrato_id,
    p_actor_id
  );
  begin
    v_token := (v_resultado->>'token')::uuid;
  exception when invalid_text_representation then
    raise exception 'Token de eliminacion invalido' using errcode = '22023';
  end;

  -- Si otro Admin retoma un intento, adopta el mismo token/manifiesto bajo los
  -- locks ya adquiridos. El borrado Storage es idempotente y puede reintentarse.
  update private.contrato_eliminaciones e
  set solicitado_por = p_actor_id
  where e.contrato_id = p_contrato_id
    and e.token = v_token;
  if not found then
    raise exception 'La preparacion de eliminacion no quedo registrada'
      using errcode = 'P0002';
  end if;

  return v_resultado;
end;
$function$;

comment on function crm.contrato_eliminacion_preparar(uuid,uuid) is
  'Prepara hard-delete linealizado por perfil Portal y contrato. Un Admin vigente puede adoptar de forma segura un intento previo conservando token/manifiesto.';

create or replace function public.crear_contrato(
  p_contrato jsonb,
  p_cronograma jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_cliente_id uuid;
begin
  if p_contrato is null or jsonb_typeof(p_contrato) <> 'object' then
    raise exception 'Faltan los datos del contrato' using errcode = '22023';
  end if;
  begin
    v_cliente_id := (p_contrato->>'cliente_id')::uuid;
  exception when invalid_text_representation then
    raise exception 'Cliente invalido' using errcode = '22023';
  end;

  perform private.bloquear_cliente_para_mutacion(v_cliente_id);
  return private.crear_contrato_f41_impl(p_contrato, p_cronograma);
end;
$function$;

comment on function public.crear_contrato(jsonb,jsonb) is
  'Entrada contractual serializada. La implementacion canonica privada conserva validaciones, capacidad atomica, producto, contrato y cronograma.';

revoke all on function public.crear_contrato(jsonb,jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.crear_contrato(jsonb,jsonb)
  to authenticated, service_role;

create or replace function public.actualizar_contrato(
  p_id uuid,
  p_contrato jsonb,
  p_cronograma jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
begin
  perform private.bloquear_contrato_para_correccion_f41(
    p_id,
    'terminos'
  );
  return private.actualizar_contrato_f41_impl(
    p_id,
    p_contrato,
    p_cronograma
  );
end;
$function$;

comment on function public.actualizar_contrato(uuid,jsonb,jsonb) is
  'Entrada de correccion serializada. Adquiere primero el perfil y delega todas las validaciones canonicas al cuerpo privado.';

revoke all on function public.actualizar_contrato(uuid,jsonb,jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.actualizar_contrato(uuid,jsonb,jsonb)
  to authenticated;

create or replace function public.cerrar_contrato(
  p_id uuid,
  p_resultado text,
  p_contrato_nuevo_id uuid default null::uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
begin
  perform private.bloquear_contrato_para_correccion_f41(p_id, 'cierre');
  return private.cerrar_contrato_f41_impl(
    p_id,
    p_resultado,
    p_contrato_nuevo_id
  );
end;
$function$;

comment on function public.cerrar_contrato(uuid,text,uuid) is
  'Cierre renovado/retirado serializado con cobros antes de delegar todas las validaciones y traslados al cuerpo canonico.';

create or replace function public.actualizar_numero_contrato(
  p_id uuid,
  p_numero text,
  p_notas text default null::text,
  p_categoria text default null::text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
begin
  perform private.bloquear_contrato_para_correccion_f41(p_id, 'numero');
  return private.actualizar_numero_contrato_f41_impl(
    p_id,
    p_numero,
    p_notas,
    p_categoria
  );
end;
$function$;

comment on function public.actualizar_numero_contrato(
  uuid,
  text,
  text,
  text
) is
  'Correccion acotada de numero/notas/categoria, serializada por autoridad, cliente y contrato antes de delegar al cuerpo canonico.';

create or replace function crm.crear_contrato_con_cuenta(
  p_contrato jsonb,
  p_cronograma jsonb,
  p_cuenta jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_cliente_id uuid;
begin
  if p_contrato is null or jsonb_typeof(p_contrato) <> 'object' then
    raise exception 'Faltan los datos del contrato' using errcode = '22023';
  end if;
  begin
    v_cliente_id := (p_contrato->>'cliente_id')::uuid;
  exception when invalid_text_representation then
    raise exception 'Cliente invalido' using errcode = '22023';
  end;

  perform private.bloquear_cliente_para_mutacion(v_cliente_id);
  return private.crear_contrato_con_cuenta_f41_impl(
    p_contrato,
    p_cronograma,
    p_cuenta
  );
end;
$function$;

comment on function crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb) is
  'Alta con cuenta serializada: perfil antes de advisory/cuenta, producto, contrato, vinculo y PDF.';

revoke all on function crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)
  from public, anon, authenticated, service_role;
grant execute on function crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)
  to authenticated;

create or replace function crm.actualizar_contrato_con_cuenta(
  p_id uuid,
  p_contrato jsonb,
  p_cronograma jsonb
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_cliente_id uuid;
begin
  select c.cliente_id
    into v_cliente_id
  from public.contratos c
  where c.id = p_id;
  if not found then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu cartera';
  end if;

  perform private.bloquear_cliente_para_mutacion(v_cliente_id);
  perform private.actualizar_contrato_con_cuenta_f41_impl(
    p_id,
    p_contrato,
    p_cronograma
  );
end;
$function$;

comment on function crm.actualizar_contrato_con_cuenta(uuid,jsonb,jsonb) is
  'Correccion con cuenta serializada: perfil antes de contrato, validacion bancaria y escritores hijos.';

revoke all on function crm.actualizar_contrato_con_cuenta(uuid,jsonb,jsonb)
  from public, anon, authenticated, service_role;
grant execute on function crm.actualizar_contrato_con_cuenta(uuid,jsonb,jsonb)
  to authenticated;

-- Alta atomica: el lock de autoridad se adquiere antes de emitir la capacidad
-- y antes de que el escritor elija/bloquee una cuenta. La capacidad conserva
-- su alcance original y se limpia aun cuando falle el escritor delegado.
create or replace function crm.crear_contrato_con_cuenta_pdf_v2(
  p_contrato jsonb,
  p_cronograma jsonb,
  p_cuenta jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor_id uuid := (select auth.uid());
  v_cliente_id uuid;
  v_capacidad_token uuid := pg_catalog.gen_random_uuid();
  v_capacidad_anterior text := current_setting(
    'crm.contrato_escritura_atomica_token',
    true
  );
  v_resultado jsonb;
  v_contrato_id uuid;
  v_pdf jsonb;
begin
  if v_actor_id is null then
    raise insufficient_privilege using message = 'Sesion no valida';
  end if;
  if p_contrato is null or jsonb_typeof(p_contrato) <> 'object' then
    raise exception 'Faltan los datos del contrato' using errcode = '22023';
  end if;
  begin
    v_cliente_id := (p_contrato->>'cliente_id')::uuid;
  exception when invalid_text_representation then
    raise exception 'Selecciona un cliente valido' using errcode = '22023';
  end;
  if v_cliente_id is null then
    raise exception 'Selecciona un cliente valido' using errcode = '22023';
  end if;

  perform private.bloquear_cliente_para_mutacion(v_cliente_id);

  insert into private.contrato_escritura_atomica_capacidades (
    token,
    backend_pid,
    transaccion_id,
    actor_id,
    operacion,
    cliente_id,
    contrato_id
  ) values (
    v_capacidad_token,
    pg_catalog.pg_backend_pid(),
    pg_catalog.txid_current(),
    v_actor_id,
    'alta',
    v_cliente_id,
    null
  );
  perform set_config(
    'crm.contrato_escritura_atomica_token',
    v_capacidad_token::text,
    true
  );

  begin
    v_resultado := crm.crear_contrato_con_cuenta(
      p_contrato,
      p_cronograma,
      p_cuenta
    );
  exception when others then
    delete from private.contrato_escritura_atomica_capacidades
    where token = v_capacidad_token;
    perform set_config(
      'crm.contrato_escritura_atomica_token',
      coalesce(v_capacidad_anterior, ''),
      true
    );
    raise;
  end;

  delete from private.contrato_escritura_atomica_capacidades
  where token = v_capacidad_token;
  perform set_config(
    'crm.contrato_escritura_atomica_token',
    coalesce(v_capacidad_anterior, ''),
    true
  );

  begin
    v_contrato_id := (v_resultado->>'id')::uuid;
  exception when invalid_text_representation then
    raise exception 'El alta no devolvio un contrato valido'
      using errcode = 'P0001';
  end;
  if v_contrato_id is null then
    raise exception 'El alta no devolvio un contrato valido'
      using errcode = 'P0001';
  end if;

  v_pdf := private.crear_job_contrato_pdf_base(v_contrato_id, v_actor_id);
  return v_resultado || jsonb_build_object('pdf', v_pdf);
end;
$function$;

comment on function crm.crear_contrato_con_cuenta_pdf_v2(
  jsonb,
  jsonb,
  jsonb
) is
  'Alta contractual atomica serializada con la asignacion vigente del cliente. El lock de perfil precede contrato, cuenta y reserva PDF.';

revoke all on function crm.crear_contrato_con_cuenta_pdf_v2(
  jsonb,
  jsonb,
  jsonb
) from public, anon, authenticated, service_role;
grant execute on function crm.crear_contrato_con_cuenta_pdf_v2(
  jsonb,
  jsonb,
  jsonb
) to authenticated;

-- Correccion atomica: una lectura inicial resuelve el cliente sin bloquear el
-- contrato; despues se fija primero la autoridad del perfil y solo entonces se
-- toma el mutex contractual/CAS. Asi todos los caminos comparten perfil ->
-- contrato -> cuenta/PDF y una reasignacion no puede confirmar entre el ultimo
-- recheck y el COMMIT de la correccion.
create or replace function crm.actualizar_contrato_con_cuenta_pdf_v3(
  p_id uuid,
  p_contrato jsonb,
  p_cronograma jsonb,
  p_revision_esperada timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor_id uuid := (select auth.uid());
  v_cliente_id uuid;
  v_cliente_bloqueado_id uuid;
  v_revision_actual timestamptz;
  v_capacidad_token uuid;
  v_capacidad_anterior text := current_setting(
    'crm.contrato_escritura_atomica_token',
    true
  );
  v_revision_anterior text := current_setting(
    'crm.contrato_pdf_revision_autorizada',
    true
  );
  v_pdf jsonb;
begin
  if v_actor_id is null then
    raise insufficient_privilege using message = 'Sesion no valida';
  end if;

  select c.cliente_id
    into v_cliente_id
  from public.contratos c
  where c.id = p_id;
  if not found then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu cartera';
  end if;

  perform private.bloquear_cliente_para_mutacion(v_cliente_id);

  select
    c.cliente_id,
    coalesce(c.actualizado_en, c.creado_en, 'epoch'::timestamptz)
    into v_cliente_bloqueado_id, v_revision_actual
  from public.contratos c
  where c.id = p_id
  for update;
  if not found
     or v_cliente_bloqueado_id is distinct from v_cliente_id
     or not private.puede_gestionar_cuentas_cliente(v_cliente_bloqueado_id) then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu cartera';
  end if;
  v_cliente_id := v_cliente_bloqueado_id;

  if private.contrato_en_eliminacion(p_id) then
    raise exception 'El contrato esta en proceso de eliminacion'
      using errcode = '55000';
  end if;

  if p_revision_esperada is null
     or p_revision_esperada is distinct from v_revision_actual then
    raise exception using
      errcode = '40001',
      message = 'El contrato cambio desde que abriste la ficha. Recarga la informacion antes de guardar.';
  end if;

  v_capacidad_token := pg_catalog.gen_random_uuid();
  insert into private.contrato_escritura_atomica_capacidades (
    token,
    backend_pid,
    transaccion_id,
    actor_id,
    operacion,
    cliente_id,
    contrato_id
  ) values (
    v_capacidad_token,
    pg_catalog.pg_backend_pid(),
    pg_catalog.txid_current(),
    v_actor_id,
    'correccion',
    v_cliente_id,
    p_id
  );
  perform set_config(
    'crm.contrato_escritura_atomica_token',
    v_capacidad_token::text,
    true
  );
  perform set_config(
    'crm.contrato_pdf_revision_autorizada',
    p_id::text,
    true
  );

  begin
    perform crm.actualizar_contrato_con_cuenta(
      p_id,
      p_contrato,
      p_cronograma
    );
  exception when others then
    delete from private.contrato_escritura_atomica_capacidades
    where token = v_capacidad_token;
    perform set_config(
      'crm.contrato_escritura_atomica_token',
      coalesce(v_capacidad_anterior, ''),
      true
    );
    perform set_config(
      'crm.contrato_pdf_revision_autorizada',
      coalesce(v_revision_anterior, ''),
      true
    );
    raise;
  end;

  delete from private.contrato_escritura_atomica_capacidades
  where token = v_capacidad_token;
  perform set_config(
    'crm.contrato_escritura_atomica_token',
    coalesce(v_capacidad_anterior, ''),
    true
  );
  perform set_config(
    'crm.contrato_pdf_revision_autorizada',
    coalesce(v_revision_anterior, ''),
    true
  );

  v_pdf := private.crear_revision_contrato_pdf_base(p_id, v_actor_id);
  return jsonb_build_object('id', p_id, 'ok', true, 'pdf', v_pdf);
end;
$function$;

comment on function crm.actualizar_contrato_con_cuenta_pdf_v3(
  uuid,
  jsonb,
  jsonb,
  timestamptz
) is
  'Correccion contractual atomica y CAS con asignacion serializada. Orden canonico: perfil, contrato, cuenta y revision PDF.';

revoke all on function crm.actualizar_contrato_con_cuenta_pdf_v3(
  uuid,
  jsonb,
  jsonb,
  timestamptz
) from public, anon, authenticated, service_role;
grant execute on function crm.actualizar_contrato_con_cuenta_pdf_v3(
  uuid,
  jsonb,
  jsonb,
  timestamptz
) to authenticated;

-- Leer un ledger sellado y crear/continuar su materializacion son capacidades
-- distintas. El gate de materializacion reutiliza el alcance mutante y veta de
-- forma expresa una membresia CRM Directorio aunque la misma identidad conserve
-- poderes administrativos en Portal.
create or replace function private.puede_materializar_contrato_pdf(
  p_contrato_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select (select auth.uid()) is not null
    and not exists (
      select 1
      from crm.equipo e
      where e.perfil_id = (select auth.uid())
        and e.activo is true
        and e.rol_crm = 'directorio'
    )
    and not exists (
      -- El rol Portal solo es fallback cuando no hay una membresia CRM
      -- operativa activa. Asi Directorio Portal + Gerencia/Supervisor/Vendedor
      -- conserva su capacidad CRM, pero Directorio CRM no puede heredar poder
      -- de Admin/Superadmin Portal.
      select 1
      from public.perfiles actor
      where actor.id = (select auth.uid())
        and actor.activo is true
        and actor.rol = 'directorio'
        and not exists (
          select 1
          from crm.equipo e
          where e.perfil_id = actor.id
            and e.activo is true
            and e.rol_crm in ('vendedor', 'supervisor', 'gerencia')
        )
    )
    and private.puede_leer_contrato_pdf(p_contrato_id)
    and exists (
      select 1
      from public.contratos c
      where c.id = p_contrato_id
        and private.puede_gestionar_cuentas_cliente(c.cliente_id)
    );
$function$;

comment on function private.puede_materializar_contrato_pdf(uuid) is
  'Autoriza una mutacion durable del PDF por alcance operativo actual. Directorio CRM nunca materializa; Directorio Portal solo veta como fallback sin membresia CRM operativa.';

revoke all on function private.puede_materializar_contrato_pdf(uuid)
  from public, anon, authenticated, service_role;

create or replace function private.puede_materializar_contrato_pdf_como(
  p_contrato_id uuid,
  p_actor_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_sub_anterior text := current_setting('request.jwt.claim.sub', true);
  v_resultado boolean;
begin
  if p_actor_id is null then return false; end if;
  perform set_config('request.jwt.claim.sub', p_actor_id::text, true);
  v_resultado := private.puede_materializar_contrato_pdf(p_contrato_id);
  perform set_config(
    'request.jwt.claim.sub',
    coalesce(v_sub_anterior, ''),
    true
  );
  return v_resultado;
exception when others then
  perform set_config(
    'request.jwt.claim.sub',
    coalesce(v_sub_anterior, ''),
    true
  );
  raise;
end;
$function$;

comment on function private.puede_materializar_contrato_pdf_como(uuid,uuid) is
  'Gate delegado para el worker service-role; evalua al actor original y restaura siempre el claim previo.';

revoke all on function private.puede_materializar_contrato_pdf_como(uuid,uuid)
  from public, anon, authenticated, service_role;

-- Compatibilidad interna: todas las llamadas historicas a la variante "como"
-- pertenecen a writers (reservar/reclamar/marcar/finalizar), no a lecturas. Al
-- redirigirlas al gate de materializacion se cierra tambien el bypass RPC
-- service-role sin duplicar autorizacion en cada etapa del worker.
create or replace function private.puede_leer_contrato_pdf_como(
  p_contrato_id uuid,
  p_actor_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select private.puede_materializar_contrato_pdf_como(
    p_contrato_id,
    p_actor_id
  );
$function$;

comment on function private.puede_leer_contrato_pdf_como(uuid,uuid) is
  'Shim privado de writers PDF legacy. Ya no representa lectura: exige la capacidad de materializacion del actor delegado.';

revoke all on function private.puede_leer_contrato_pdf_como(uuid,uuid)
  from public, anon, authenticated, service_role;

-- El worker usa service_role, pero cada etapa debe quedar linealizada contra
-- cambios de rol, jerarquia, baja y reasignacion del actor original. La llave
-- de jerarquia se toma antes de perfil/contrato; despues se fijan ambas filas
-- hasta COMMIT y se revalida la capacidad con el snapshot ya bloqueado.
create or replace function private.bloquear_contrato_pdf_para_materializar(
  p_contrato_id uuid
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_actor_id uuid;
  v_cliente_id uuid;
  v_cliente_bloqueado_id uuid;
  v_cliente_actual_id uuid;
begin
  v_actor_id := (select auth.uid());
  if v_actor_id is null or p_contrato_id is null then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu cartera';
  end if;

  if not private.puede_materializar_contrato_pdf(p_contrato_id) then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu cartera';
  end if;

  select c.cliente_id
    into v_cliente_id
  from public.contratos c
  where c.id = p_contrato_id;
  if not found then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu cartera';
  end if;

  perform pg_catalog.pg_advisory_xact_lock_shared(
    pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0)
  );
  perform pg_catalog.pg_advisory_xact_lock_shared(
    pg_catalog.hashtextextended(
      'public.cronograma_pagos.cobros_f41',
      0
    )
  );

  perform 1
  from public.perfiles actor
  where actor.id = v_actor_id
    and actor.activo is true
  for share;
  if not found then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu cartera';
  end if;

  select p.id
    into v_cliente_bloqueado_id
  from public.perfiles p
  where p.id = v_cliente_id
    and p.rol = 'cliente'
  for share;
  if not found then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu cartera';
  end if;

  -- Se toma UPDATE desde el inicio: SHARE + posterior elevacion dentro del
  -- cuerpo canonico permitiria que dos workers del mismo contrato quedaran
  -- en deadlock al intentar convertirse mutuamente a UPDATE.
  select c.cliente_id
    into v_cliente_actual_id
  from public.contratos c
  where c.id = p_contrato_id
  for update;

  if not found
     or v_cliente_actual_id is distinct from v_cliente_bloqueado_id
     or not private.puede_materializar_contrato_pdf(p_contrato_id) then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu cartera';
  end if;
end;
$function$;

comment on function private.bloquear_contrato_pdf_para_materializar(uuid) is
  'Congela jerarquia, asignacion y contrato antes de una etapa durable del worker PDF y revalida la capacidad del actor JWT.';

revoke all on function private.bloquear_contrato_pdf_para_materializar(uuid)
  from public, anon, authenticated, service_role;

create or replace function private.bloquear_contrato_pdf_para_materializar_como(
  p_contrato_id uuid,
  p_actor_id uuid
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_sub_anterior text := current_setting('request.jwt.claim.sub', true);
begin
  if p_actor_id is null then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu cartera';
  end if;
  perform set_config('request.jwt.claim.sub', p_actor_id::text, true);
  perform private.bloquear_contrato_pdf_para_materializar(p_contrato_id);
  perform set_config(
    'request.jwt.claim.sub',
    coalesce(v_sub_anterior, ''),
    true
  );
exception when others then
  perform set_config(
    'request.jwt.claim.sub',
    coalesce(v_sub_anterior, ''),
    true
  );
  raise;
end;
$function$;

comment on function private.bloquear_contrato_pdf_para_materializar_como(uuid,uuid) is
  'Guardia delegada del worker: evalua y bloquea como el actor original, restaura el claim y conserva los locks hasta COMMIT.';

revoke all on function private.bloquear_contrato_pdf_para_materializar_como(
  uuid,
  uuid
) from public, anon, authenticated, service_role;

-- Los cinco writers service-role ya bloquean job/contrato dentro de sus cuerpos
-- canonicos. Se clonan y se envuelven in-place para anteponer autoridad ->
-- perfil -> contrato, preservando OID, owner y ACL de cada firma publica.
create temporary table f41_pdf_writer_oids (
  firma text primary key,
  oid_original oid not null
);

insert into f41_pdf_writer_oids (firma, oid_original) values
  (
    'crm.contrato_pdf_reservar(uuid,uuid)',
    'crm.contrato_pdf_reservar(uuid,uuid)'::regprocedure::oid
  ),
  (
    'crm.contrato_pdf_reclamar(uuid,uuid,integer)',
    'crm.contrato_pdf_reclamar(uuid,uuid,integer)'::regprocedure::oid
  ),
  (
    'crm.contrato_pdf_marcar_subido(uuid,uuid,uuid,text,bigint)',
    'crm.contrato_pdf_marcar_subido(uuid,uuid,uuid,text,bigint)'::regprocedure::oid
  ),
  (
    'crm.contrato_pdf_marcar_error(uuid,uuid,uuid,text)',
    'crm.contrato_pdf_marcar_error(uuid,uuid,uuid,text)'::regprocedure::oid
  ),
  (
    'crm.contrato_pdf_finalizar(uuid,uuid,uuid)',
    'crm.contrato_pdf_finalizar(uuid,uuid,uuid)'::regprocedure::oid
  );

do $clonar_writers_pdf$
declare
  v_item record;
  v_definicion text;
  v_clon text;
  v_propietario name;
begin
  for v_item in
    select *
    from (values
      (
        'crm.contrato_pdf_reservar(uuid,uuid)',
        'FUNCTION crm.contrato_pdf_reservar(',
        'FUNCTION private.contrato_pdf_reservar_f41_impl(',
        'private.contrato_pdf_reservar_f41_impl(uuid,uuid)',
        'private.crear_job_contrato_pdf_base',
        'p_actor_id'
      ),
      (
        'crm.contrato_pdf_reclamar(uuid,uuid,integer)',
        'FUNCTION crm.contrato_pdf_reclamar(',
        'FUNCTION private.contrato_pdf_reclamar_f41_impl(',
        'private.contrato_pdf_reclamar_f41_impl(uuid,uuid,integer)',
        'private.bloquear_fila_contrato_pdf',
        'private.puede_leer_contrato_pdf_como'
      ),
      (
        'crm.contrato_pdf_marcar_subido(uuid,uuid,uuid,text,bigint)',
        'FUNCTION crm.contrato_pdf_marcar_subido(',
        'FUNCTION private.contrato_pdf_marcar_subido_f41_impl(',
        'private.contrato_pdf_marcar_subido_f41_impl(uuid,uuid,uuid,text,bigint)',
        'private.bloquear_fila_contrato_pdf',
        'subido_verificado'
      ),
      (
        'crm.contrato_pdf_marcar_error(uuid,uuid,uuid,text)',
        'FUNCTION crm.contrato_pdf_marcar_error(',
        'FUNCTION private.contrato_pdf_marcar_error_f41_impl(',
        'private.contrato_pdf_marcar_error_f41_impl(uuid,uuid,uuid,text)',
        'private.bloquear_fila_contrato_pdf',
        'error_reintentable'
      ),
      (
        'crm.contrato_pdf_finalizar(uuid,uuid,uuid)',
        'FUNCTION crm.contrato_pdf_finalizar(',
        'FUNCTION private.contrato_pdf_finalizar_f41_impl(',
        'private.contrato_pdf_finalizar_f41_impl(uuid,uuid,uuid)',
        'private.bloquear_fila_contrato_pdf',
        'insert into private.contrato_pdfs'
      )
    ) as esperado(
      firma,
      cabecera,
      cabecera_clon,
      firma_clon,
      marcador_uno,
      marcador_dos
    )
  loop
    select pg_catalog.pg_get_functiondef(
      pg_catalog.to_regprocedure(v_item.firma)
    ) into v_definicion;
    if v_definicion not ilike '%' || v_item.marcador_uno || '%'
       or v_definicion not ilike '%' || v_item.marcador_dos || '%' then
      raise exception
        'PREFLIGHT F41: % no es el writer PDF canonico esperado',
        v_item.firma;
    end if;
    if (
      pg_catalog.length(v_definicion)
        - pg_catalog.length(
          pg_catalog.replace(v_definicion, v_item.cabecera, '')
        )
    ) / pg_catalog.length(v_item.cabecera) <> 1 then
      raise exception 'PREFLIGHT F41: cabecera ambigua en %', v_item.firma;
    end if;
    v_clon := pg_catalog.replace(
      v_definicion,
      v_item.cabecera,
      v_item.cabecera_clon
    );
    execute v_clon;
    select r.rolname into strict v_propietario
    from pg_catalog.pg_proc p
    join pg_catalog.pg_roles r on r.oid = p.proowner
    where p.oid = pg_catalog.to_regprocedure(v_item.firma);
    execute pg_catalog.format(
      'alter function %s owner to %I',
      v_item.firma_clon,
      v_propietario
    );
  end loop;
end;
$clonar_writers_pdf$;

revoke all on function private.contrato_pdf_reservar_f41_impl(uuid,uuid)
  from public, anon, authenticated, service_role;
revoke all on function private.contrato_pdf_reclamar_f41_impl(
  uuid,
  uuid,
  integer
) from public, anon, authenticated, service_role;
revoke all on function private.contrato_pdf_marcar_subido_f41_impl(
  uuid,
  uuid,
  uuid,
  text,
  bigint
) from public, anon, authenticated, service_role;
revoke all on function private.contrato_pdf_marcar_error_f41_impl(
  uuid,
  uuid,
  uuid,
  text
) from public, anon, authenticated, service_role;
revoke all on function private.contrato_pdf_finalizar_f41_impl(
  uuid,
  uuid,
  uuid
) from public, anon, authenticated, service_role;

create or replace function crm.contrato_pdf_reservar(
  p_contrato_id uuid,
  p_actor_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
begin
  perform private.bloquear_contrato_pdf_para_materializar_como(
    p_contrato_id,
    p_actor_id
  );
  return private.contrato_pdf_reservar_f41_impl(
    p_contrato_id,
    p_actor_id
  );
end;
$function$;

create or replace function crm.contrato_pdf_reclamar(
  p_contrato_id uuid,
  p_actor_id uuid,
  p_lease_segundos integer default 120
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
begin
  perform private.bloquear_contrato_pdf_para_materializar_como(
    p_contrato_id,
    p_actor_id
  );
  return private.contrato_pdf_reclamar_f41_impl(
    p_contrato_id,
    p_actor_id,
    p_lease_segundos
  );
end;
$function$;

create or replace function crm.contrato_pdf_marcar_subido(
  p_job_id uuid,
  p_lease_token uuid,
  p_actor_id uuid,
  p_sha256 text,
  p_bytes bigint
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_contrato_id uuid;
begin
  select j.contrato_id into v_contrato_id
  from private.contrato_pdf_jobs j
  where j.id = p_job_id;
  if not found then
    raise exception 'Job PDF no encontrado' using errcode = 'P0002';
  end if;
  perform private.bloquear_contrato_pdf_para_materializar_como(
    v_contrato_id,
    p_actor_id
  );
  return private.contrato_pdf_marcar_subido_f41_impl(
    p_job_id,
    p_lease_token,
    p_actor_id,
    p_sha256,
    p_bytes
  );
end;
$function$;

create or replace function crm.contrato_pdf_marcar_error(
  p_job_id uuid,
  p_lease_token uuid,
  p_actor_id uuid,
  p_error_codigo text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_contrato_id uuid;
begin
  select j.contrato_id into v_contrato_id
  from private.contrato_pdf_jobs j
  where j.id = p_job_id;
  if not found then
    raise exception 'Job PDF no encontrado' using errcode = 'P0002';
  end if;
  perform private.bloquear_contrato_pdf_para_materializar_como(
    v_contrato_id,
    p_actor_id
  );
  return private.contrato_pdf_marcar_error_f41_impl(
    p_job_id,
    p_lease_token,
    p_actor_id,
    p_error_codigo
  );
end;
$function$;

create or replace function crm.contrato_pdf_finalizar(
  p_job_id uuid,
  p_lease_token uuid,
  p_actor_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_contrato_id uuid;
begin
  select j.contrato_id into v_contrato_id
  from private.contrato_pdf_jobs j
  where j.id = p_job_id;
  if not found then
    raise exception 'Job PDF no encontrado' using errcode = 'P0002';
  end if;
  perform private.bloquear_contrato_pdf_para_materializar_como(
    v_contrato_id,
    p_actor_id
  );
  return private.contrato_pdf_finalizar_f41_impl(
    p_job_id,
    p_lease_token,
    p_actor_id
  );
end;
$function$;

revoke all on function crm.contrato_pdf_reservar(uuid,uuid)
  from public, anon, authenticated, service_role;
revoke all on function crm.contrato_pdf_reclamar(uuid,uuid,integer)
  from public, anon, authenticated, service_role;
revoke all on function crm.contrato_pdf_marcar_subido(
  uuid,
  uuid,
  uuid,
  text,
  bigint
) from public, anon, authenticated, service_role;
revoke all on function crm.contrato_pdf_marcar_error(
  uuid,
  uuid,
  uuid,
  text
) from public, anon, authenticated, service_role;
revoke all on function crm.contrato_pdf_finalizar(uuid,uuid,uuid)
  from public, anon, authenticated, service_role;

grant execute on function crm.contrato_pdf_reservar(uuid,uuid)
  to service_role;
grant execute on function crm.contrato_pdf_reclamar(uuid,uuid,integer)
  to service_role;
grant execute on function crm.contrato_pdf_marcar_subido(
  uuid,
  uuid,
  uuid,
  text,
  bigint
) to service_role;
grant execute on function crm.contrato_pdf_marcar_error(
  uuid,
  uuid,
  uuid,
  text
) to service_role;
grant execute on function crm.contrato_pdf_finalizar(uuid,uuid,uuid)
  to service_role;

-- Gate autenticado y sin efectos laterales para que Edge falle antes de usar
-- service role. Devuelve false tanto para UUID inexistente como fuera de alcance.
create or replace function crm.contrato_pdf_puede_materializar_fn(
  p_contrato_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select private.puede_materializar_contrato_pdf(p_contrato_id);
$function$;

comment on function crm.contrato_pdf_puede_materializar_fn(uuid) is
  'Capacidad previa, sin escrituras, para action=ensure. La autorizacion efectiva se repite dentro de cada writer SQL.';

revoke all on function crm.contrato_pdf_puede_materializar_fn(uuid)
  from public, anon, authenticated, service_role;
grant execute on function crm.contrato_pdf_puede_materializar_fn(uuid)
  to authenticated;

do $postflight$
declare
  v_lock pg_catalog.pg_proc%rowtype;
  v_public_crear pg_catalog.pg_proc%rowtype;
  v_public_actualizar pg_catalog.pg_proc%rowtype;
  v_crm_crear pg_catalog.pg_proc%rowtype;
  v_crm_actualizar pg_catalog.pg_proc%rowtype;
  v_impl_crear pg_catalog.pg_proc%rowtype;
  v_impl_actualizar pg_catalog.pg_proc%rowtype;
  v_impl_crm_crear pg_catalog.pg_proc%rowtype;
  v_impl_crm_actualizar pg_catalog.pg_proc%rowtype;
  v_alta pg_catalog.pg_proc%rowtype;
  v_correccion pg_catalog.pg_proc%rowtype;
  v_lectura pg_catalog.pg_proc%rowtype;
  v_materializa pg_catalog.pg_proc%rowtype;
  v_materializa_como pg_catalog.pg_proc%rowtype;
  v_shim pg_catalog.pg_proc%rowtype;
  v_rpc pg_catalog.pg_proc%rowtype;
  v_lock_src text;
  v_mutex_jerarquia_shared constant text :=
    'pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtextextended(''crm.equipo.usuarios_jerarquia'',0))';
  v_mutex_cobros_shared constant text :=
    'pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtextextended(''public.cronograma_pagos.cobros_f41'',0))';
begin
  select p.* into v_lock from pg_catalog.pg_proc p
  where p.oid = 'private.bloquear_cliente_para_mutacion(uuid)'::regprocedure;
  select p.* into v_public_crear from pg_catalog.pg_proc p
  where p.oid = 'public.crear_contrato(jsonb,jsonb)'::regprocedure;
  select p.* into v_public_actualizar from pg_catalog.pg_proc p
  where p.oid =
    'public.actualizar_contrato(uuid,jsonb,jsonb)'::regprocedure;
  select p.* into v_crm_crear from pg_catalog.pg_proc p
  where p.oid =
    'crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)'::regprocedure;
  select p.* into v_crm_actualizar from pg_catalog.pg_proc p
  where p.oid =
    'crm.actualizar_contrato_con_cuenta(uuid,jsonb,jsonb)'::regprocedure;
  select p.* into v_impl_crear from pg_catalog.pg_proc p
  where p.oid = 'private.crear_contrato_f41_impl(jsonb,jsonb)'::regprocedure;
  select p.* into v_impl_actualizar from pg_catalog.pg_proc p
  where p.oid =
    'private.actualizar_contrato_f41_impl(uuid,jsonb,jsonb)'::regprocedure;
  select p.* into v_impl_crm_crear from pg_catalog.pg_proc p
  where p.oid =
    'private.crear_contrato_con_cuenta_f41_impl(jsonb,jsonb,jsonb)'::regprocedure;
  select p.* into v_impl_crm_actualizar from pg_catalog.pg_proc p
  where p.oid =
    'private.actualizar_contrato_con_cuenta_f41_impl(uuid,jsonb,jsonb)'::regprocedure;
  select p.* into v_alta from pg_catalog.pg_proc p
  where p.oid =
    'crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)'::regprocedure;
  select p.* into v_correccion from pg_catalog.pg_proc p
  where p.oid =
    'crm.actualizar_contrato_con_cuenta_pdf_v3(uuid,jsonb,jsonb,timestamptz)'::regprocedure;
  select p.* into v_lectura from pg_catalog.pg_proc p
  where p.oid = 'private.puede_leer_contrato_pdf(uuid)'::regprocedure;
  select p.* into v_materializa from pg_catalog.pg_proc p
  where p.oid =
    'private.puede_materializar_contrato_pdf(uuid)'::regprocedure;
  select p.* into v_materializa_como from pg_catalog.pg_proc p
  where p.oid =
    'private.puede_materializar_contrato_pdf_como(uuid,uuid)'::regprocedure;
  select p.* into v_shim from pg_catalog.pg_proc p
  where p.oid =
    'private.puede_leer_contrato_pdf_como(uuid,uuid)'::regprocedure;
  select p.* into v_rpc from pg_catalog.pg_proc p
  where p.oid =
    'crm.contrato_pdf_puede_materializar_fn(uuid)'::regprocedure;
  v_lock_src := pg_catalog.regexp_replace(
    pg_catalog.lower(v_lock.prosrc),
    '[[:space:]]+',
    '',
    'g'
  );

  if v_public_crear.oid <> (
       select g.oid_original from pg_temp.f41_writer_oids g
       where g.firma = 'public.crear_contrato(jsonb,jsonb)'
     )
     or v_public_actualizar.oid <> (
       select g.oid_original from pg_temp.f41_writer_oids g
       where g.firma = 'public.actualizar_contrato(uuid,jsonb,jsonb)'
     )
     or v_crm_crear.oid <> (
       select g.oid_original from pg_temp.f41_writer_oids g
       where g.firma = 'crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)'
     )
     or v_crm_actualizar.oid <> (
       select g.oid_original from pg_temp.f41_writer_oids g
       where g.firma = 'crm.actualizar_contrato_con_cuenta(uuid,jsonb,jsonb)'
     )
     or v_impl_crear.oid = v_public_crear.oid
     or v_impl_actualizar.oid = v_public_actualizar.oid
     or v_impl_crm_crear.oid = v_crm_crear.oid
     or v_impl_crm_actualizar.oid = v_crm_actualizar.oid
     or v_impl_crear.proowner <> v_public_crear.proowner
     or v_impl_actualizar.proowner <> v_public_actualizar.proowner
     or v_impl_crm_crear.proowner <> v_crm_crear.proowner
     or v_impl_crm_actualizar.proowner <> v_crm_actualizar.proowner then
    raise exception
      'POSTFLIGHT F41-00: OID/owner de writers no se preservo de forma segura';
  end if;

  if not v_lock.prosecdef
     or v_lock.provolatile <> 'v'
     or not (v_lock.proconfig @> array['search_path=""'])
     or v_lock.prosrc not ilike '%for share%'
     or v_lock.prosrc not ilike '%puede_gestionar_cuentas_cliente%'
     or pg_catalog.strpos(v_lock_src, v_mutex_jerarquia_shared) = 0
     or pg_catalog.strpos(v_lock_src, v_mutex_cobros_shared) = 0
     or pg_catalog.strpos(
       v_lock_src,
       v_mutex_jerarquia_shared
     ) >= pg_catalog.strpos(v_lock_src, v_mutex_cobros_shared)
     or pg_catalog.strpos(
       pg_catalog.lower(v_lock.prosrc),
       'public.cronograma_pagos.cobros_f41'
     ) = 0
     or pg_catalog.strpos(
       pg_catalog.lower(v_lock.prosrc),
       'public.cronograma_pagos.cobros_f41'
     ) >= pg_catalog.strpos(
       pg_catalog.lower(v_lock.prosrc),
       'for share'
     )
     or pg_catalog.has_function_privilege(
       'authenticated',
       'private.bloquear_cliente_para_mutacion(uuid)',
       'EXECUTE'
     ) then
    raise exception 'POSTFLIGHT F41-01: guardia de asignacion insegura';
  end if;

  if not v_alta.prosecdef
     or v_alta.provolatile <> 'v'
     or not (v_alta.proconfig @> array['search_path=""'])
     or pg_catalog.strpos(
       pg_catalog.lower(v_alta.prosrc),
       'bloquear_cliente_para_mutacion'
     ) = 0
     or pg_catalog.strpos(
       pg_catalog.lower(v_alta.prosrc),
       'bloquear_cliente_para_mutacion'
     ) >= pg_catalog.strpos(
       pg_catalog.lower(v_alta.prosrc),
       'insert into private.contrato_escritura_atomica_capacidades'
     )
     or not v_correccion.prosecdef
     or v_correccion.provolatile <> 'v'
     or not (v_correccion.proconfig @> array['search_path=""'])
     or pg_catalog.strpos(
       pg_catalog.lower(v_correccion.prosrc),
       'bloquear_cliente_para_mutacion'
     ) = 0
     or pg_catalog.strpos(
       pg_catalog.lower(v_correccion.prosrc),
       'bloquear_cliente_para_mutacion'
     ) >= pg_catalog.strpos(
       pg_catalog.lower(v_correccion.prosrc),
       'for update'
     )
     or v_correccion.pronargdefaults <> 1 then
    raise exception 'POSTFLIGHT F41-02: orden de locks contractual inseguro';
  end if;

  if not v_public_crear.prosecdef
     or v_public_crear.provolatile <> 'v'
     or not (v_public_crear.proconfig @> array['search_path=""'])
     or pg_catalog.strpos(
       pg_catalog.lower(v_public_crear.prosrc),
       'bloquear_cliente_para_mutacion'
     ) = 0
     or pg_catalog.strpos(
       pg_catalog.lower(v_public_crear.prosrc),
       'bloquear_cliente_para_mutacion'
     ) >= pg_catalog.strpos(
       pg_catalog.lower(v_public_crear.prosrc),
       'private.crear_contrato_f41_impl'
     )
     or not v_public_actualizar.prosecdef
     or v_public_actualizar.provolatile <> 'v'
     or not (v_public_actualizar.proconfig @> array['search_path=""'])
     or pg_catalog.strpos(
       pg_catalog.lower(v_public_actualizar.prosrc),
       'bloquear_contrato_para_correccion_f41'
     ) = 0
     or pg_catalog.strpos(
       pg_catalog.lower(v_public_actualizar.prosrc),
       'bloquear_contrato_para_correccion_f41'
     ) >= pg_catalog.strpos(
       pg_catalog.lower(v_public_actualizar.prosrc),
       'private.actualizar_contrato_f41_impl'
     )
     or not v_crm_crear.prosecdef
     or v_crm_crear.provolatile <> 'v'
     or not (v_crm_crear.proconfig @> array['search_path=""'])
     or pg_catalog.strpos(
       pg_catalog.lower(v_crm_crear.prosrc),
       'bloquear_cliente_para_mutacion'
     ) = 0
     or pg_catalog.strpos(
       pg_catalog.lower(v_crm_crear.prosrc),
       'bloquear_cliente_para_mutacion'
     ) >= pg_catalog.strpos(
       pg_catalog.lower(v_crm_crear.prosrc),
       'private.crear_contrato_con_cuenta_f41_impl'
     )
     or not v_crm_actualizar.prosecdef
     or v_crm_actualizar.provolatile <> 'v'
     or not (v_crm_actualizar.proconfig @> array['search_path=""'])
     or pg_catalog.strpos(
       pg_catalog.lower(v_crm_actualizar.prosrc),
       'bloquear_cliente_para_mutacion'
     ) = 0
     or pg_catalog.strpos(
       pg_catalog.lower(v_crm_actualizar.prosrc),
       'bloquear_cliente_para_mutacion'
     ) >= pg_catalog.strpos(
       pg_catalog.lower(v_crm_actualizar.prosrc),
       'private.actualizar_contrato_con_cuenta_f41_impl'
     ) then
    raise exception 'POSTFLIGHT F41-03: alguna entrada directa elude la guardia';
  end if;

  if not v_impl_crear.prosecdef
     or v_impl_crear.prosrc not ilike '%tiene_capacidad_contrato_atomico%'
     or v_impl_crear.prosrc not ilike '%puede_gestionar_cuentas_cliente%'
     or not v_impl_actualizar.prosecdef
     or v_impl_actualizar.prosrc not ilike '%tiene_capacidad_contrato_atomico%'
     or v_impl_actualizar.prosrc not ilike '%puede_gestionar_cuentas_cliente%'
     or not v_impl_crm_crear.prosecdef
     or v_impl_crm_crear.prosrc not ilike '%pg_advisory_xact_lock%'
     or v_impl_crm_crear.prosrc not ilike '%public.crear_contrato%'
     or not v_impl_crm_actualizar.prosecdef
     or v_impl_crm_actualizar.prosrc not ilike '%public.actualizar_contrato%'
     or v_impl_crm_actualizar.prosrc not ilike '%puede_gestionar_cuentas_cliente%'
     or pg_catalog.has_function_privilege(
       'authenticated',
       'private.crear_contrato_f41_impl(jsonb,jsonb)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'service_role',
       'private.crear_contrato_f41_impl(jsonb,jsonb)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticated',
       'private.actualizar_contrato_f41_impl(uuid,jsonb,jsonb)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticated',
       'private.crear_contrato_con_cuenta_f41_impl(jsonb,jsonb,jsonb)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticated',
       'private.actualizar_contrato_con_cuenta_f41_impl(uuid,jsonb,jsonb)',
       'EXECUTE'
     ) then
    raise exception 'POSTFLIGHT F41-04: implementaciones privadas inseguras';
  end if;

  if not v_lectura.prosecdef
     or v_lectura.provolatile <> 's'
     or not (v_lectura.proconfig @> array['search_path=""'])
     or v_lectura.prosrc not ilike '%puede_ver_contrato%'
     or not v_materializa.prosecdef
     or v_materializa.provolatile <> 's'
     or not (v_materializa.proconfig @> array['search_path=""'])
     or v_materializa.prosrc not ilike '%puede_gestionar_cuentas_cliente%'
     or v_materializa.prosrc not ilike '%puede_leer_contrato_pdf%'
     or v_materializa.prosrc not ilike '%directorio%'
     or not v_materializa_como.prosecdef
     or v_materializa_como.provolatile <> 's'
     or not (v_materializa_como.proconfig @> array['search_path=""'])
     or v_shim.prosrc not ilike '%puede_materializar_contrato_pdf_como%'
     or not v_rpc.prosecdef
     or v_rpc.provolatile <> 's'
     or not (v_rpc.proconfig @> array['search_path=""']) then
    raise exception 'POSTFLIGHT F41-05: lectura y materializacion no quedaron separadas';
  end if;

  if not pg_catalog.has_function_privilege(
       'authenticated',
       'crm.contrato_pdf_puede_materializar_fn(uuid)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'anon',
       'crm.contrato_pdf_puede_materializar_fn(uuid)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'service_role',
       'crm.contrato_pdf_puede_materializar_fn(uuid)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticated',
       'private.puede_materializar_contrato_pdf(uuid)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticated',
       'private.puede_materializar_contrato_pdf_como(uuid,uuid)',
       'EXECUTE'
     ) then
    raise exception 'POSTFLIGHT F41-06: ACL de materializacion inesperada';
  end if;

  if not pg_catalog.has_function_privilege(
       'authenticated', 'public.crear_contrato(jsonb,jsonb)', 'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'service_role', 'public.crear_contrato(jsonb,jsonb)', 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'anon', 'public.crear_contrato(jsonb,jsonb)', 'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'authenticated',
       'public.actualizar_contrato(uuid,jsonb,jsonb)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'service_role',
       'public.actualizar_contrato(uuid,jsonb,jsonb)',
       'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'authenticated',
       'crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'service_role',
       'crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)',
       'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'authenticated',
       'crm.actualizar_contrato_con_cuenta(uuid,jsonb,jsonb)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'service_role',
       'crm.actualizar_contrato_con_cuenta(uuid,jsonb,jsonb)',
       'EXECUTE'
     ) then
    raise exception 'POSTFLIGHT F41-07: ACL de escritores inesperada';
  end if;
end;
$postflight$;

do $postflight_extra_writers$
declare
  v_lock_actor pg_catalog.pg_proc%rowtype;
  v_lock_correccion pg_catalog.pg_proc%rowtype;
  v_cierre pg_catalog.pg_proc%rowtype;
  v_cierre_impl pg_catalog.pg_proc%rowtype;
  v_numero pg_catalog.pg_proc%rowtype;
  v_numero_impl pg_catalog.pg_proc%rowtype;
  v_numero_pdf pg_catalog.pg_proc%rowtype;
  v_lock_delete pg_catalog.pg_proc%rowtype;
  v_delete_prepare pg_catalog.pg_proc%rowtype;
  v_delete_impl pg_catalog.pg_proc%rowtype;
  v_delete_finalize pg_catalog.pg_proc%rowtype;
  v_restore_delete_trigger pg_catalog.pg_proc%rowtype;
  v_original pg_catalog.pg_proc%rowtype;
  v_clon pg_catalog.pg_proc%rowtype;
  v_snapshot record;
  v_item record;
  v_lock_correccion_src text;
  v_lock_delete_src text;
  v_delete_finalize_src text;
  v_restore_delete_src text;
  v_mutex_jerarquia_shared constant text :=
    'pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtextextended(''crm.equipo.usuarios_jerarquia'',0))';
  v_mutex_cobros_shared constant text :=
    'pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtextextended(''public.cronograma_pagos.cobros_f41'',0))';
  v_mutex_cobros_exclusive constant text :=
    'pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(''public.cronograma_pagos.cobros_f41'',0))';
begin
  if (select count(*) from pg_temp.f41_guarded_snapshots) <> 9 then
    raise exception 'POSTFLIGHT F41-11: snapshots de firmas incompletos';
  end if;

  select p.* into strict v_lock_actor
  from pg_catalog.pg_proc p
  where p.oid =
    'private.bloquear_actor_mutador_equipo_f41(text)'::regprocedure;
  if not v_lock_actor.prosecdef
     or v_lock_actor.provolatile <> 'v'
     or not (v_lock_actor.proconfig @> array['search_path=""'])
     or pg_catalog.strpos(
       pg_catalog.lower(v_lock_actor.prosrc),
       'pg_advisory_xact_lock('
     ) = 0
     or pg_catalog.strpos(
       pg_catalog.lower(v_lock_actor.prosrc),
       'pg_advisory_xact_lock('
     ) >= pg_catalog.strpos(
       pg_catalog.lower(v_lock_actor.prosrc),
       'for share'
     )
     or pg_catalog.strpos(
       pg_catalog.lower(v_lock_actor.prosrc),
       'pg_advisory_xact_lock_shared'
     ) <> 0
     or v_lock_actor.prosrc not ilike '%public.perfiles actor%'
     or (
       pg_catalog.length(pg_catalog.lower(v_lock_actor.prosrc))
         - pg_catalog.length(pg_catalog.replace(
             pg_catalog.lower(v_lock_actor.prosrc),
             'private.es_superadmin_portal_activo',
             ''
           ))
     ) / pg_catalog.length('private.es_superadmin_portal_activo') < 2
     or (
       pg_catalog.length(pg_catalog.lower(v_lock_actor.prosrc))
         - pg_catalog.length(pg_catalog.replace(
             pg_catalog.lower(v_lock_actor.prosrc),
             'private.es_gerencia_crm_activa',
             ''
           ))
     ) / pg_catalog.length('private.es_gerencia_crm_activa') < 2
     or pg_catalog.has_function_privilege(
       'authenticated',
       'private.bloquear_actor_mutador_equipo_f41(text)',
       'EXECUTE'
     ) then
    raise exception 'POSTFLIGHT F41-12: guardia de mutadores insegura';
  end if;

  select p.* into strict v_lock_correccion
  from pg_catalog.pg_proc p
  where p.oid =
    'private.bloquear_contrato_para_correccion_f41(uuid,text)'::regprocedure;
  v_lock_correccion_src := pg_catalog.regexp_replace(
    pg_catalog.lower(v_lock_correccion.prosrc),
    '[[:space:]]+',
    '',
    'g'
  );
  if not v_lock_correccion.prosecdef
     or v_lock_correccion.provolatile <> 'v'
     or not (v_lock_correccion.proconfig @> array['search_path=""'])
     or v_lock_correccion.prosrc not ilike '%public.es_gestor_cartera%'
     or v_lock_correccion.prosrc not ilike '%public.es_admin%'
     or v_lock_correccion.prosrc not ilike '%private.membresia_crm_revocada%'
     or v_lock_correccion.prosrc not ilike '%private.puede_gestionar_cuentas_cliente%'
     or v_lock_correccion.prosrc not ilike '%public.perfiles actor%'
     or v_lock_correccion.prosrc not ilike '%public.perfiles cliente%'
     or pg_catalog.strpos(
       v_lock_correccion_src,
       v_mutex_jerarquia_shared
     ) = 0
     or pg_catalog.strpos(
       v_lock_correccion_src,
       v_mutex_cobros_shared
     ) = 0
     or pg_catalog.strpos(
       v_lock_correccion_src,
       v_mutex_jerarquia_shared
     ) >= pg_catalog.strpos(
       v_lock_correccion_src,
       v_mutex_cobros_shared
     )
     or pg_catalog.strpos(
       pg_catalog.lower(v_lock_correccion.prosrc),
       'public.cronograma_pagos.cobros_f41'
     ) = 0
     or pg_catalog.strpos(
       pg_catalog.lower(v_lock_correccion.prosrc),
       'public.cronograma_pagos.cobros_f41'
     ) >= pg_catalog.strpos(
       pg_catalog.lower(v_lock_correccion.prosrc),
       'for share'
     )
     or pg_catalog.strpos(
       pg_catalog.lower(v_lock_correccion.prosrc),
       'for share'
     ) >= pg_catalog.strpos(
       pg_catalog.lower(v_lock_correccion.prosrc),
       'for update'
     )
     or pg_catalog.has_function_privilege(
       'authenticated',
       'private.bloquear_contrato_para_correccion_f41(uuid,text)',
       'EXECUTE'
     ) then
    raise exception 'POSTFLIGHT F41-12B: guardia de correccion insegura';
  end if;

  select p.* into strict v_cierre
  from pg_catalog.pg_proc p
  where p.oid = 'public.cerrar_contrato(uuid,text,uuid)'::regprocedure;
  select p.* into strict v_cierre_impl
  from pg_catalog.pg_proc p
  where p.oid =
    'private.cerrar_contrato_f41_impl(uuid,text,uuid)'::regprocedure;
  select * into strict v_snapshot
  from pg_temp.f41_guarded_snapshots s
  where s.firma = 'public.cerrar_contrato(uuid,text,uuid)';

  if v_cierre.oid <> v_snapshot.oid_original
     or v_cierre.proowner <> v_snapshot.owner_original
     or v_cierre.proacl is distinct from v_snapshot.acl_original
     or v_cierre.oid = v_cierre_impl.oid
     or v_cierre.proowner <> v_cierre_impl.proowner
     or not v_cierre.prosecdef
     or v_cierre.provolatile <> 'v'
     or not (v_cierre.proconfig @> array['search_path=""'])
     or v_cierre.pronargdefaults <> 1
     or pg_catalog.strpos(
       pg_catalog.lower(v_cierre.prosrc),
       'bloquear_contrato_para_correccion_f41'
     ) = 0
     or pg_catalog.strpos(
       pg_catalog.lower(v_cierre.prosrc),
       'bloquear_contrato_para_correccion_f41'
     ) >= pg_catalog.strpos(
       pg_catalog.lower(v_cierre.prosrc),
       'private.cerrar_contrato_f41_impl'
     )
     or not v_cierre_impl.prosecdef
     or v_cierre_impl.prosrc not ilike '%es_admin()%'
     or v_cierre_impl.prosrc not ilike '%update cronograma_pagos%'
     or pg_catalog.has_function_privilege(
       'anon',
       'private.cerrar_contrato_f41_impl(uuid,text,uuid)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticated',
       'private.cerrar_contrato_f41_impl(uuid,text,uuid)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'service_role',
       'private.cerrar_contrato_f41_impl(uuid,text,uuid)',
       'EXECUTE'
     ) then
    raise exception 'POSTFLIGHT F41-12C: cierre contractual inseguro';
  end if;

  select p.* into strict v_numero
  from pg_catalog.pg_proc p
  where p.oid =
    'public.actualizar_numero_contrato(uuid,text,text,text)'::regprocedure;
  select p.* into strict v_numero_impl
  from pg_catalog.pg_proc p
  where p.oid =
    'private.actualizar_numero_contrato_f41_impl(uuid,text,text,text)'::regprocedure;
  select p.* into strict v_numero_pdf
  from pg_catalog.pg_proc p
  where p.oid =
    'crm.actualizar_numero_contrato_pdf_v3(uuid,text,text,text)'::regprocedure;
  select * into strict v_snapshot
  from pg_temp.f41_guarded_snapshots s
  where s.firma = 'public.actualizar_numero_contrato(uuid,text,text,text)';

  if v_numero.oid <> v_snapshot.oid_original
     or v_numero.proowner <> v_snapshot.owner_original
     or v_numero.proacl is distinct from v_snapshot.acl_original
     or v_numero.oid = v_numero_impl.oid
     or v_numero.proowner <> v_numero_impl.proowner
     or not v_numero.prosecdef
     or v_numero.provolatile <> 'v'
     or not (v_numero.proconfig @> array['search_path=""'])
     or v_numero.pronargdefaults <> 2
     or pg_catalog.strpos(
       pg_catalog.lower(v_numero.prosrc),
       'bloquear_contrato_para_correccion_f41'
     ) = 0
     or pg_catalog.strpos(
       pg_catalog.lower(v_numero.prosrc),
       'bloquear_contrato_para_correccion_f41'
     ) >= pg_catalog.strpos(
       pg_catalog.lower(v_numero.prosrc),
       'private.actualizar_numero_contrato_f41_impl'
     )
     or not v_numero_impl.prosecdef
     or v_numero_impl.prosrc not ilike '%public.es_gestor_cartera%'
     or v_numero_impl.prosrc not ilike '%private.membresia_crm_revocada%'
     or pg_catalog.has_function_privilege(
       'authenticated',
       'private.actualizar_numero_contrato_f41_impl(uuid,text,text,text)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'service_role',
       'private.actualizar_numero_contrato_f41_impl(uuid,text,text,text)',
       'EXECUTE'
     ) then
    raise exception 'POSTFLIGHT F41-13: correccion de numero insegura';
  end if;

  select * into strict v_snapshot
  from pg_temp.f41_guarded_snapshots s
  where s.firma = 'crm.actualizar_numero_contrato_pdf_v3(uuid,text,text,text)';
  if v_numero_pdf.oid <> v_snapshot.oid_original
     or v_numero_pdf.proowner <> v_snapshot.owner_original
     or v_numero_pdf.proacl is distinct from v_snapshot.acl_original
     or not v_numero_pdf.prosecdef
     or v_numero_pdf.pronargdefaults <> 2
     or v_numero_pdf.prosrc not ilike '%public.actualizar_numero_contrato%'
     or v_numero_pdf.prosrc not ilike '%private.crear_revision_contrato_pdf_base%'
     or not pg_catalog.has_function_privilege(
       'authenticated',
       'crm.actualizar_numero_contrato_pdf_v3(uuid,text,text,text)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'anon',
       'crm.actualizar_numero_contrato_pdf_v3(uuid,text,text,text)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'service_role',
       'crm.actualizar_numero_contrato_pdf_v3(uuid,text,text,text)',
       'EXECUTE'
     ) then
    raise exception 'POSTFLIGHT F41-14: wrapper PDF de numero inseguro';
  end if;

  for v_item in
    select *
    from (values
      (
        'crm.asignar_rol_usuario_fn(uuid,text,timestamptz,uuid)',
        'private.asignar_rol_usuario_f41_impl(uuid,text,timestamptz,uuid)',
        'private.asignar_rol_usuario_f41_impl',
        'superadmin'
      ),
      (
        'crm.actualizar_jerarquia_usuario_fn(uuid,uuid,timestamptz,uuid)',
        'private.actualizar_jerarquia_usuario_f41_impl(uuid,uuid,timestamptz,uuid)',
        'private.actualizar_jerarquia_usuario_f41_impl',
        'gerencia'
      ),
      (
        'crm.fijar_membresia_activa_fn(uuid,boolean,uuid,timestamptz,uuid)',
        'private.fijar_membresia_activa_f41_impl(uuid,boolean,uuid,timestamptz,uuid)',
        'private.fijar_membresia_activa_f41_impl',
        'gerencia'
      ),
      (
        'crm.registrar_vendedor_usuario_fn(uuid,text,text,text,text,text,text,text,uuid,uuid)',
        'private.registrar_vendedor_usuario_f41_impl(uuid,text,text,text,text,text,text,text,uuid,uuid)',
        'private.registrar_vendedor_usuario_f41_impl',
        'gerencia'
      )
    ) as firmas(original, clon, llamada_clon, autoridad)
  loop
    select p.* into strict v_original
    from pg_catalog.pg_proc p
    where p.oid = v_item.original::regprocedure;
    select p.* into strict v_clon
    from pg_catalog.pg_proc p
    where p.oid = v_item.clon::regprocedure;
    select * into strict v_snapshot
    from pg_temp.f41_guarded_snapshots s
    where s.firma = v_item.original;

    if v_original.oid <> v_snapshot.oid_original
       or v_original.proowner <> v_snapshot.owner_original
       or v_original.proacl is distinct from v_snapshot.acl_original
       or v_original.oid = v_clon.oid
       or v_original.proowner <> v_clon.proowner
       or not v_original.prosecdef
       or v_original.provolatile <> 'v'
       or not (v_original.proconfig @> array['search_path=""'])
       or v_original.pronargdefaults <> 0
       or pg_catalog.strpos(
         pg_catalog.lower(v_original.prosrc),
         'bloquear_actor_mutador_equipo_f41'
       ) = 0
       or pg_catalog.strpos(
         pg_catalog.lower(v_original.prosrc),
         'bloquear_actor_mutador_equipo_f41'
       ) >= pg_catalog.strpos(
         pg_catalog.lower(v_original.prosrc),
         pg_catalog.lower(v_item.llamada_clon)
       )
       or v_original.prosrc not ilike '%' || v_item.autoridad || '%'
       or not v_clon.prosecdef
       or v_clon.provolatile <> 'v'
       or not (v_clon.proconfig @> array['search_path=""'])
       or v_clon.pronargdefaults <> 0
       or pg_catalog.has_function_privilege(
         'anon', v_item.original, 'EXECUTE'
       )
       or not pg_catalog.has_function_privilege(
         'authenticated', v_item.original, 'EXECUTE'
       )
       or pg_catalog.has_function_privilege(
         'service_role', v_item.original, 'EXECUTE'
       )
       or pg_catalog.has_function_privilege(
         'anon', v_item.clon, 'EXECUTE'
       )
       or pg_catalog.has_function_privilege(
         'authenticated', v_item.clon, 'EXECUTE'
       )
       or pg_catalog.has_function_privilege(
         'service_role', v_item.clon, 'EXECUTE'
       ) then
      raise exception
        'POSTFLIGHT F41-15: mutador exclusivo inseguro: %',
        v_item.original;
    end if;
  end loop;

  select p.* into strict v_lock_delete
  from pg_catalog.pg_proc p
  where p.oid =
    'private.bloquear_actor_eliminacion_contrato_f41(uuid)'::regprocedure;
  select p.* into strict v_delete_prepare
  from pg_catalog.pg_proc p
  where p.oid =
    'crm.contrato_eliminacion_preparar(uuid,uuid)'::regprocedure;
  select p.* into strict v_delete_impl
  from pg_catalog.pg_proc p
  where p.oid =
    'private.contrato_eliminacion_preparar_f41_impl(uuid,uuid)'::regprocedure;
  select p.* into strict v_delete_finalize
  from pg_catalog.pg_proc p
  where p.oid =
    'crm.contrato_eliminacion_finalizar(uuid,uuid,uuid)'::regprocedure;
  select p.* into strict v_restore_delete_trigger
  from pg_catalog.pg_proc p
  where p.oid =
    'private.trg_restaurar_operacion_antes_borrar_contrato()'::regprocedure;
  v_lock_delete_src := pg_catalog.regexp_replace(
    pg_catalog.lower(v_lock_delete.prosrc),
    '[[:space:]]+',
    '',
    'g'
  );
  v_delete_finalize_src := pg_catalog.regexp_replace(
    pg_catalog.lower(v_delete_finalize.prosrc),
    '[[:space:]]+',
    '',
    'g'
  );
  v_restore_delete_src := pg_catalog.regexp_replace(
    pg_catalog.lower(v_restore_delete_trigger.prosrc),
    '[[:space:]]+',
    '',
    'g'
  );

  if not v_lock_delete.prosecdef
     or v_lock_delete.provolatile <> 'v'
     or not (v_lock_delete.proconfig @> array['search_path=""'])
     or v_lock_delete.prosrc not ilike '%public.perfiles actor%'
     or v_lock_delete.prosrc not ilike '%for share%'
     or v_lock_delete.prosrc not ilike '%admin%superadmin%'
     or v_lock_delete.prosrc not ilike '%v_actor_valido := found%'
     or pg_catalog.strpos(
       v_lock_delete_src,
       'selectexists(select1frompublic.perfilesactor'
     ) = 0
     or pg_catalog.strpos(
       v_lock_delete_src,
       'selectexists(select1frompublic.perfilesactor'
     ) >= pg_catalog.strpos(
       v_lock_delete_src,
       v_mutex_jerarquia_shared
     )
     or (
       pg_catalog.length(v_lock_delete_src)
         - pg_catalog.length(pg_catalog.replace(
           v_lock_delete_src,
           'actor.activoistrue',
           ''
         ))
     ) / pg_catalog.length('actor.activoistrue') <> 2
     or (
       pg_catalog.length(v_lock_delete_src)
         - pg_catalog.length(pg_catalog.replace(
           v_lock_delete_src,
           'actor.rolin(''admin'',''superadmin'')',
           ''
         ))
     ) / pg_catalog.length('actor.rolin(''admin'',''superadmin'')') <> 2
     or pg_catalog.strpos(
       v_lock_delete_src,
       v_mutex_jerarquia_shared
     ) = 0
     or pg_catalog.strpos(
       v_lock_delete_src,
       v_mutex_cobros_exclusive
     ) = 0
     or pg_catalog.strpos(
       v_lock_delete_src,
       v_mutex_cobros_shared
     ) <> 0
     or pg_catalog.strpos(
       v_lock_delete_src,
       v_mutex_jerarquia_shared
     ) >= pg_catalog.strpos(
       v_lock_delete_src,
       v_mutex_cobros_exclusive
     )
     or pg_catalog.strpos(
       v_lock_delete_src,
       v_mutex_cobros_exclusive
     ) >= pg_catalog.strpos(v_lock_delete_src, 'forshare')
     or pg_catalog.has_function_privilege(
       'authenticated',
       'private.bloquear_actor_eliminacion_contrato_f41(uuid)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'service_role',
       'private.bloquear_actor_eliminacion_contrato_f41(uuid)',
       'EXECUTE'
     ) then
    raise exception 'POSTFLIGHT F41-16: guardia de hard-delete insegura';
  end if;

  select * into strict v_snapshot
  from pg_temp.f41_guarded_snapshots s
  where s.firma = 'crm.contrato_eliminacion_preparar(uuid,uuid)';
  if v_delete_prepare.oid <> v_snapshot.oid_original
     or v_delete_prepare.proowner <> v_snapshot.owner_original
     or v_delete_prepare.proacl is distinct from v_snapshot.acl_original
     or v_delete_prepare.oid = v_delete_impl.oid
     or v_delete_prepare.proowner <> v_delete_impl.proowner
     or not v_delete_prepare.prosecdef
     or v_delete_prepare.provolatile <> 'v'
     or not (v_delete_prepare.proconfig @> array['search_path=""'])
     or pg_catalog.strpos(
       pg_catalog.lower(v_delete_prepare.prosrc),
       'bloquear_actor_eliminacion_contrato_f41'
     ) = 0
     or pg_catalog.strpos(
       pg_catalog.lower(v_delete_prepare.prosrc),
       'bloquear_actor_eliminacion_contrato_f41'
     ) >= pg_catalog.strpos(
       pg_catalog.lower(v_delete_prepare.prosrc),
       'private.contrato_eliminacion_preparar_f41_impl'
     )
     or v_delete_prepare.prosrc not ilike '%set solicitado_por = p_actor_id%'
     or not v_delete_impl.prosecdef
     or v_delete_impl.prosrc not ilike '%private.bloquear_fila_contrato_pdf%'
     or v_delete_impl.prosrc not ilike '%private.poder_eliminar_contrato_como%'
     or pg_catalog.has_function_privilege(
       'authenticated',
       'crm.contrato_eliminacion_preparar(uuid,uuid)',
       'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'service_role',
       'crm.contrato_eliminacion_preparar(uuid,uuid)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'service_role',
       'private.contrato_eliminacion_preparar_f41_impl(uuid,uuid)',
       'EXECUTE'
     ) then
    raise exception 'POSTFLIGHT F41-17: preparar hard-delete inseguro';
  end if;

  select * into strict v_snapshot
  from pg_temp.f41_guarded_snapshots s
  where s.firma = 'crm.contrato_eliminacion_finalizar(uuid,uuid,uuid)';
  if v_delete_finalize.oid <> v_snapshot.oid_original
     or v_delete_finalize.proowner <> v_snapshot.owner_original
     or v_delete_finalize.proacl is distinct from v_snapshot.acl_original
     or not v_delete_finalize.prosecdef
     or v_delete_finalize.prosrc not ilike '%private.bloquear_fila_contrato_pdf%'
     or pg_catalog.strpos(
       v_delete_finalize_src,
       v_mutex_jerarquia_shared
     ) = 0
     or pg_catalog.strpos(
       v_delete_finalize_src,
       v_mutex_cobros_exclusive
     ) = 0
     or pg_catalog.strpos(
       v_delete_finalize_src,
       v_mutex_jerarquia_shared
     ) >= pg_catalog.strpos(
       v_delete_finalize_src,
       v_mutex_cobros_exclusive
     )
     or pg_catalog.strpos(
       pg_catalog.lower(v_delete_finalize.prosrc),
       'pg_advisory_xact_lock_shared'
     ) = 0
     or pg_catalog.strpos(
       pg_catalog.lower(v_delete_finalize.prosrc),
       'pg_advisory_xact_lock_shared'
     ) >= pg_catalog.strpos(
       pg_catalog.lower(v_delete_finalize.prosrc),
       'pg_advisory_xact_lock('
     )
     or pg_catalog.strpos(
       pg_catalog.lower(v_delete_finalize.prosrc),
       'pg_advisory_xact_lock('
     ) >= pg_catalog.strpos(
       pg_catalog.lower(v_delete_finalize.prosrc),
       'public.cronograma_pagos.cobros_f41'
     )
     or pg_catalog.strpos(
       pg_catalog.lower(v_delete_finalize.prosrc),
       'public.cronograma_pagos.cobros_f41'
     ) >= pg_catalog.strpos(
       pg_catalog.lower(v_delete_finalize.prosrc),
       'private.bloquear_fila_contrato_pdf'
     )
     or v_delete_finalize.prosrc not ilike
       '%crm.contrato_pdf_eliminacion_autorizada%'
     or not v_restore_delete_trigger.prosecdef
     or not (
       v_restore_delete_trigger.proconfig @> array['search_path=""']
     )
     or pg_catalog.strpos(
       v_restore_delete_src,
       'updatepublic.cronograma_pagos'
     ) = 0
     or pg_catalog.strpos(
       v_restore_delete_src,
       'updatepublic.contratos'
     ) = 0
     or pg_catalog.strpos(
       v_restore_delete_src,
       'updatepublic.cronograma_pagos'
     ) >= pg_catalog.strpos(
       v_restore_delete_src,
       'updatepublic.contratos'
     )
     or not exists (
       select 1
       from pg_catalog.pg_trigger trigger
       where trigger.tgrelid = 'public.contratos'::regclass
         and trigger.tgname = 'trg_contratos_05_restaurar_operacion'
         and not trigger.tgisinternal
         and trigger.tgfoid = v_restore_delete_trigger.oid
     )
     or pg_catalog.has_function_privilege(
       'authenticated',
       'crm.contrato_eliminacion_finalizar(uuid,uuid,uuid)',
       'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'service_role',
       'crm.contrato_eliminacion_finalizar(uuid,uuid,uuid)',
       'EXECUTE'
     ) then
    raise exception 'POSTFLIGHT F41-18: finalizar hard-delete inseguro';
  end if;
end;
$postflight_extra_writers$;

do $postflight_pdf_writers$
declare
  v_lock_cliente pg_catalog.pg_proc%rowtype;
  v_lock_pdf pg_catalog.pg_proc%rowtype;
  v_lock_pdf_como pg_catalog.pg_proc%rowtype;
  v_item record;
  v_original pg_catalog.pg_proc%rowtype;
  v_clon pg_catalog.pg_proc%rowtype;
  v_lock_cliente_src text;
  v_lock_pdf_src text;
  v_mutex_jerarquia_shared constant text :=
    'pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtextextended(''crm.equipo.usuarios_jerarquia'',0))';
  v_mutex_cobros_shared constant text :=
    'pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtextextended(''public.cronograma_pagos.cobros_f41'',0))';
begin
  select p.* into strict v_lock_cliente
  from pg_catalog.pg_proc p
  where p.oid = 'private.bloquear_cliente_para_mutacion(uuid)'::regprocedure;
  select p.* into strict v_lock_pdf
  from pg_catalog.pg_proc p
  where p.oid =
    'private.bloquear_contrato_pdf_para_materializar(uuid)'::regprocedure;
  select p.* into strict v_lock_pdf_como
  from pg_catalog.pg_proc p
  where p.oid =
    'private.bloquear_contrato_pdf_para_materializar_como(uuid,uuid)'::regprocedure;
  v_lock_cliente_src := pg_catalog.regexp_replace(
    pg_catalog.lower(v_lock_cliente.prosrc),
    '[[:space:]]+',
    '',
    'g'
  );
  v_lock_pdf_src := pg_catalog.regexp_replace(
    pg_catalog.lower(v_lock_pdf.prosrc),
    '[[:space:]]+',
    '',
    'g'
  );

  if pg_catalog.strpos(
       v_lock_cliente_src,
       v_mutex_jerarquia_shared
     ) = 0
     or pg_catalog.strpos(
       v_lock_cliente_src,
       v_mutex_cobros_shared
     ) = 0
     or pg_catalog.strpos(
       v_lock_cliente_src,
       v_mutex_jerarquia_shared
     ) >= pg_catalog.strpos(
       v_lock_cliente_src,
       v_mutex_cobros_shared
     )
     or pg_catalog.strpos(
       pg_catalog.lower(v_lock_cliente.prosrc),
       'public.cronograma_pagos.cobros_f41'
     ) = 0
     or pg_catalog.strpos(
       pg_catalog.lower(v_lock_cliente.prosrc),
       'public.cronograma_pagos.cobros_f41'
     ) >= pg_catalog.strpos(
       pg_catalog.lower(v_lock_cliente.prosrc),
       'for share'
     )
     or v_lock_cliente.prosrc not ilike '%public.perfiles actor%'
     or not v_lock_pdf.prosecdef
     or v_lock_pdf.provolatile <> 'v'
     or not (v_lock_pdf.proconfig @> array['search_path=""'])
     or pg_catalog.strpos(
       v_lock_pdf_src,
       v_mutex_jerarquia_shared
     ) = 0
     or pg_catalog.strpos(
       v_lock_pdf_src,
       v_mutex_cobros_shared
     ) = 0
     or pg_catalog.strpos(
       v_lock_pdf_src,
       v_mutex_jerarquia_shared
     ) >= pg_catalog.strpos(
       v_lock_pdf_src,
       v_mutex_cobros_shared
     )
     or pg_catalog.strpos(
       pg_catalog.lower(v_lock_pdf.prosrc),
       'pg_advisory_xact_lock_shared'
     ) = 0
     or pg_catalog.strpos(
       pg_catalog.lower(v_lock_pdf.prosrc),
       'pg_advisory_xact_lock_shared'
     ) >= pg_catalog.strpos(
       pg_catalog.lower(v_lock_pdf.prosrc),
       'for share'
     )
     or pg_catalog.strpos(
       pg_catalog.lower(v_lock_pdf.prosrc),
       'for share'
     ) >= pg_catalog.strpos(
       pg_catalog.lower(v_lock_pdf.prosrc),
       'for update'
     )
     or v_lock_pdf.prosrc not ilike '%public.perfiles actor%'
     or v_lock_pdf.prosrc ilike '%for share of p, c%'
     or v_lock_pdf.prosrc not ilike
       '%puede_materializar_contrato_pdf%'
     or not v_lock_pdf_como.prosecdef
     or v_lock_pdf_como.provolatile <> 'v'
     or not (v_lock_pdf_como.proconfig @> array['search_path=""'])
     or v_lock_pdf_como.prosrc not ilike
       '%bloquear_contrato_pdf_para_materializar%'
     or pg_catalog.has_function_privilege(
       'authenticated',
       'private.bloquear_contrato_pdf_para_materializar(uuid)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'service_role',
       'private.bloquear_contrato_pdf_para_materializar_como(uuid,uuid)',
       'EXECUTE'
     ) then
    raise exception
      'POSTFLIGHT F41-08: guardia PDF o jerarquia no quedo linealizada';
  end if;

  for v_item in
    select *
    from (values
      (
        'crm.contrato_pdf_reservar(uuid,uuid)',
        'private.contrato_pdf_reservar_f41_impl(uuid,uuid)',
        'private.contrato_pdf_reservar_f41_impl'
      ),
      (
        'crm.contrato_pdf_reclamar(uuid,uuid,integer)',
        'private.contrato_pdf_reclamar_f41_impl(uuid,uuid,integer)',
        'private.contrato_pdf_reclamar_f41_impl'
      ),
      (
        'crm.contrato_pdf_marcar_subido(uuid,uuid,uuid,text,bigint)',
        'private.contrato_pdf_marcar_subido_f41_impl(uuid,uuid,uuid,text,bigint)',
        'private.contrato_pdf_marcar_subido_f41_impl'
      ),
      (
        'crm.contrato_pdf_marcar_error(uuid,uuid,uuid,text)',
        'private.contrato_pdf_marcar_error_f41_impl(uuid,uuid,uuid,text)',
        'private.contrato_pdf_marcar_error_f41_impl'
      ),
      (
        'crm.contrato_pdf_finalizar(uuid,uuid,uuid)',
        'private.contrato_pdf_finalizar_f41_impl(uuid,uuid,uuid)',
        'private.contrato_pdf_finalizar_f41_impl'
      )
    ) as firmas(original, clon, llamada_clon)
  loop
    select p.* into strict v_original
    from pg_catalog.pg_proc p
    where p.oid = pg_catalog.to_regprocedure(v_item.original);
    select p.* into strict v_clon
    from pg_catalog.pg_proc p
    where p.oid = pg_catalog.to_regprocedure(v_item.clon);

    if v_original.oid <> (
         select guardado.oid_original
         from pg_temp.f41_pdf_writer_oids guardado
         where guardado.firma = v_item.original
       )
       or v_original.oid = v_clon.oid
       or v_original.proowner <> v_clon.proowner
       or not v_original.prosecdef
       or v_original.provolatile <> 'v'
       or not (v_original.proconfig @> array['search_path=""'])
       or pg_catalog.strpos(
         pg_catalog.lower(v_original.prosrc),
         'bloquear_contrato_pdf_para_materializar_como'
       ) = 0
       or pg_catalog.strpos(
         pg_catalog.lower(v_original.prosrc),
         'bloquear_contrato_pdf_para_materializar_como'
       ) >= pg_catalog.strpos(
         pg_catalog.lower(v_original.prosrc),
         pg_catalog.lower(v_item.llamada_clon)
       )
       or not v_clon.prosecdef
       or pg_catalog.has_function_privilege(
         'authenticated', v_item.original, 'EXECUTE'
       )
       or pg_catalog.has_function_privilege(
         'anon', v_item.original, 'EXECUTE'
       )
       or not pg_catalog.has_function_privilege(
         'service_role', v_item.original, 'EXECUTE'
       )
       or pg_catalog.has_function_privilege(
         'authenticated', v_item.clon, 'EXECUTE'
       )
       or pg_catalog.has_function_privilege(
         'service_role', v_item.clon, 'EXECUTE'
       ) then
      raise exception
        'POSTFLIGHT F41-09: writer PDF inseguro: %',
        v_item.original;
    end if;
  end loop;

  if (
       select p.pronargdefaults
       from pg_catalog.pg_proc p
       where p.oid =
         'crm.contrato_pdf_reclamar(uuid,uuid,integer)'::regprocedure
     ) <> 1 then
    raise exception 'POSTFLIGHT F41-10: se perdio default del lease PDF';
  end if;
end;
$postflight_pdf_writers$;

do $postflight_cronograma_pago$
declare
  v_actor_guard pg_catalog.pg_proc%rowtype;
  v_statement_fn pg_catalog.pg_proc%rowtype;
  v_cobro_trigger pg_catalog.pg_trigger%rowtype;
  v_trigger_columns text[];
  v_trigger_fn pg_catalog.pg_proc%rowtype;
  v_pdf_lock pg_catalog.pg_proc%rowtype;
  v_snapshot record;
  v_pdf_snapshot record;
  v_using text;
  v_check text;
  v_actor_guard_src text;
  v_statement_src text;
  v_pdf_lock_src text;
  v_mutex_jerarquia_shared constant text :=
    'pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtextextended(''crm.equipo.usuarios_jerarquia'',0))';
  v_mutex_cobros_shared constant text :=
    'pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtextextended(''public.cronograma_pagos.cobros_f41'',0))';
  v_mutex_cobros_exclusive constant text :=
    'pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(''public.cronograma_pagos.cobros_f41'',0))';
begin
  select p.* into strict v_actor_guard
  from pg_catalog.pg_proc p
  where p.oid =
    'private.bloquear_actor_cobro_directo_f41()'::regprocedure;
  select p.* into strict v_statement_fn
  from pg_catalog.pg_proc p
  where p.oid =
    'private.bloquear_cronograma_cobro_statement_f41()'::regprocedure;
  select trigger.* into strict v_cobro_trigger
  from pg_catalog.pg_trigger trigger
  where trigger.tgrelid = 'public.cronograma_pagos'::regclass
    and trigger.tgname = 'trg_cronograma_pagos_00_cobro_mutex_f41'
    and not trigger.tgisinternal;
  select pg_catalog.array_agg(
    atributo.attname::text order by posicion.ordinalidad
  ) into strict v_trigger_columns
  from pg_catalog.unnest(
    v_cobro_trigger.tgattr::smallint[]
  ) with ordinality as posicion(attnum, ordinalidad)
  join pg_catalog.pg_attribute atributo
    on atributo.attrelid = v_cobro_trigger.tgrelid
   and atributo.attnum = posicion.attnum;
  select p.* into strict v_trigger_fn
  from pg_catalog.pg_proc p
  where p.oid =
    'private.proteger_cronograma_documental()'::regprocedure;
  select * into strict v_snapshot
  from pg_temp.f41_cronograma_trigger_snapshot;
  select p.* into strict v_pdf_lock
  from pg_catalog.pg_proc p
  where p.oid =
    'private.bloquear_fila_contrato_pdf(uuid)'::regprocedure;
  select * into strict v_pdf_snapshot
  from pg_temp.f41_contrato_pdf_lock_snapshot;
  select
    pg_catalog.pg_get_expr(policy.polqual, policy.polrelid),
    pg_catalog.pg_get_expr(policy.polwithcheck, policy.polrelid)
    into strict v_using, v_check
  from pg_catalog.pg_policy policy
  where policy.polrelid = 'public.cronograma_pagos'::regclass
    and policy.polname = 'cronograma_admin_actualiza'
    and policy.polcmd = 'w'
    and policy.polpermissive;
  v_actor_guard_src := pg_catalog.regexp_replace(
    pg_catalog.lower(v_actor_guard.prosrc),
    '[[:space:]]+',
    '',
    'g'
  );
  v_statement_src := pg_catalog.regexp_replace(
    pg_catalog.lower(v_statement_fn.prosrc),
    '[[:space:]]+',
    '',
    'g'
  );
  v_pdf_lock_src := pg_catalog.regexp_replace(
    pg_catalog.lower(v_pdf_lock.prosrc),
    '[[:space:]]+',
    '',
    'g'
  );

  if (
       select count(*)
       from pg_catalog.pg_policy policy
       where policy.polrelid = 'public.cronograma_pagos'::regclass
         and policy.polcmd = 'w'
         and policy.polpermissive
     ) <> 1
     or v_using not ilike '%es_gestor_cartera()%'
     or v_check not ilike '%es_gestor_cartera()%'
     or v_using ilike '%bloquear_%'
     or v_check ilike '%bloquear_%'
     or not v_actor_guard.prosecdef
     or v_actor_guard.provolatile <> 'v'
     or not (v_actor_guard.proconfig @> array['search_path=""'])
     or pg_catalog.strpos(
       v_actor_guard_src,
       v_mutex_jerarquia_shared
     ) = 0
     or pg_catalog.strpos(
       v_actor_guard_src,
       v_mutex_cobros_exclusive
     ) = 0
     or pg_catalog.strpos(
       v_actor_guard_src,
       v_mutex_jerarquia_shared
     ) >= pg_catalog.strpos(
       v_actor_guard_src,
       v_mutex_cobros_exclusive
     )
     or pg_catalog.strpos(
       pg_catalog.lower(v_actor_guard.prosrc),
       'pg_trigger_depth()'
     ) = 0
     or pg_catalog.strpos(
       pg_catalog.lower(v_actor_guard.prosrc),
       'pg_advisory_xact_lock_shared'
     ) = 0
     or pg_catalog.strpos(
       pg_catalog.lower(v_actor_guard.prosrc),
       'pg_advisory_xact_lock_shared'
     ) >= pg_catalog.strpos(
       pg_catalog.lower(v_actor_guard.prosrc),
       'pg_advisory_xact_lock('
     )
     or pg_catalog.strpos(
       pg_catalog.lower(v_actor_guard.prosrc),
       'pg_advisory_xact_lock('
     ) = 0
     or pg_catalog.strpos(
       pg_catalog.lower(v_actor_guard.prosrc),
       'pg_advisory_xact_lock('
     ) >= pg_catalog.strpos(
       pg_catalog.lower(v_actor_guard.prosrc),
       'public.cronograma_pagos.cobros_f41'
     )
     or pg_catalog.strpos(
       pg_catalog.lower(v_actor_guard.prosrc),
       'public.cronograma_pagos.cobros_f41'
     ) >= pg_catalog.strpos(
       pg_catalog.lower(v_actor_guard.prosrc),
       'for share'
     )
     or pg_catalog.strpos(
       pg_catalog.lower(v_actor_guard.prosrc),
       'for update'
     ) <> 0
     or (
       pg_catalog.length(pg_catalog.lower(v_actor_guard.prosrc))
         - pg_catalog.length(pg_catalog.replace(
           pg_catalog.lower(v_actor_guard.prosrc),
           'public.es_gestor_cartera',
           ''
         ))
     ) / pg_catalog.length('public.es_gestor_cartera') < 2
     or not pg_catalog.has_function_privilege(
       'authenticated',
       'private.bloquear_actor_cobro_directo_f41()',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'anon',
       'private.bloquear_actor_cobro_directo_f41()',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'service_role',
       'private.bloquear_actor_cobro_directo_f41()',
       'EXECUTE'
     )
     or v_statement_fn.prosecdef
     or v_statement_fn.provolatile <> 'v'
     or not (v_statement_fn.proconfig @> array['search_path=""'])
     or v_statement_fn.prosrc not ilike
       '%current_user = ''authenticated''%'
     or v_statement_fn.prosrc not ilike
       '%elsif current_user = ''service_role'' then%'
     or v_statement_fn.prosrc not ilike
       '%private.bloquear_actor_cobro_directo_f41()%'
     or pg_catalog.lower(v_statement_fn.prosrc) ~
       E'(^|\\n)[[:space:]]*else[[:space:]]*($|\\n)'
     or (
       pg_catalog.length(v_statement_src)
         - pg_catalog.length(pg_catalog.replace(
           v_statement_src,
           'current_user',
           ''
         ))
     ) / pg_catalog.length('current_user') <> 2
     or pg_catalog.strpos(
       v_statement_src,
       v_mutex_jerarquia_shared
     ) = 0
     or pg_catalog.strpos(
       v_statement_src,
       v_mutex_cobros_exclusive
     ) = 0
     or pg_catalog.strpos(
       v_statement_src,
       v_mutex_cobros_shared
     ) <> 0
     or pg_catalog.strpos(
       v_statement_src,
       v_mutex_jerarquia_shared
     ) >= pg_catalog.strpos(
       v_statement_src,
       v_mutex_cobros_exclusive
     )
     or v_cobro_trigger.tgfoid <> v_statement_fn.oid
     or v_cobro_trigger.tgtype <> 18
     or v_cobro_trigger.tgenabled <> 'O'
     or v_trigger_columns is distinct from array[
       'estado',
       'fecha_pago_real',
       'monto_pagado',
       'registrado_por'
     ]::text[]
     or pg_catalog.has_function_privilege(
       'anon',
       'private.bloquear_cronograma_cobro_statement_f41()',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticated',
       'private.bloquear_cronograma_cobro_statement_f41()',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'service_role',
       'private.bloquear_cronograma_cobro_statement_f41()',
       'EXECUTE'
  ) then
    raise exception
      'POSTFLIGHT F41-19A: cobro REST no quedo protegido antes de filas';
  end if;

  if v_trigger_fn.oid <> v_snapshot.oid_original
     or v_trigger_fn.proowner <> v_snapshot.owner_original
     or v_trigger_fn.proacl is distinct from v_snapshot.acl_original
     or v_trigger_fn.prosecdef is distinct from
       v_snapshot.security_definer_original
     or v_trigger_fn.provolatile is distinct from
       v_snapshot.volatilidad_original
     or v_trigger_fn.proconfig is distinct from v_snapshot.config_original
     or pg_catalog.strpos(
       pg_catalog.lower(v_trigger_fn.prosrc),
       'notif_pago_enviada_en'
     ) = 0
     or pg_catalog.strpos(
       pg_catalog.lower(v_trigger_fn.prosrc),
       'recordatorio_3d_enviado_en'
     ) = 0
     or pg_catalog.strpos(
       pg_catalog.lower(v_trigger_fn.prosrc),
       'pg_catalog.to_jsonb(new)'
     ) = 0
     or pg_catalog.strpos(
       pg_catalog.lower(v_trigger_fn.prosrc),
       'pg_catalog.to_jsonb(new)'
     ) >= pg_catalog.strpos(
       pg_catalog.lower(v_trigger_fn.prosrc),
       'private.bloquear_contratos_hijo_documental'
     )
     or pg_catalog.strpos(
       pg_catalog.lower(v_trigger_fn.prosrc),
       'if not v_cambio_documental then'
     ) = 0
     or pg_catalog.strpos(
       pg_catalog.lower(v_trigger_fn.prosrc),
       'if not v_cambio_documental then'
     ) >= pg_catalog.strpos(
       pg_catalog.lower(v_trigger_fn.prosrc),
       'private.contrato_en_eliminacion'
     )
     or pg_catalog.strpos(
       pg_catalog.lower(v_trigger_fn.prosrc),
       'private.contrato_en_eliminacion'
     ) >= pg_catalog.strpos(
       pg_catalog.lower(v_trigger_fn.prosrc),
       'private.bloquear_contratos_hijo_documental'
     )
     or not exists (
       select 1
       from pg_catalog.pg_trigger trigger
       where trigger.tgrelid = 'public.cronograma_pagos'::regclass
         and trigger.tgname =
           'trg_cronograma_pagos_00_documental_congelado'
         and not trigger.tgisinternal
         and trigger.tgfoid = v_trigger_fn.oid
     ) then
    raise exception
      'POSTFLIGHT F41-19B: trigger de cronograma perdio fidelidad';
  end if;

  if v_pdf_lock.oid <> v_pdf_snapshot.oid_original
     or v_pdf_lock.proowner <> v_pdf_snapshot.owner_original
     or v_pdf_lock.proacl is distinct from v_pdf_snapshot.acl_original
     or v_pdf_lock.prosecdef is distinct from
       v_pdf_snapshot.security_definer_original
     or v_pdf_lock.provolatile is distinct from
       v_pdf_snapshot.volatilidad_original
     or v_pdf_lock.proconfig is distinct from v_pdf_snapshot.config_original
     or pg_catalog.strpos(
       v_pdf_lock_src,
       v_mutex_cobros_shared
     ) = 0
     or pg_catalog.strpos(
       v_pdf_lock_src,
       v_mutex_cobros_shared
     ) >= pg_catalog.strpos(v_pdf_lock_src, 'forupdate')
     or pg_catalog.strpos(
       pg_catalog.lower(v_pdf_lock.prosrc),
       'public.cronograma_pagos.cobros_f41'
     ) = 0
     or pg_catalog.strpos(
       pg_catalog.lower(v_pdf_lock.prosrc),
       'public.cronograma_pagos.cobros_f41'
     ) >= pg_catalog.strpos(
       pg_catalog.lower(v_pdf_lock.prosrc),
       'for update'
     ) then
    raise exception
      'POSTFLIGHT F41-19C: lock contractual/PDF no comparte mutex de cobros';
  end if;
end;
$postflight_cronograma_pago$;

do $postflight_acl_contratos$
begin
  if exists (
       select 1
       from pg_catalog.unnest(array['anon', 'authenticated']) as rol(nombre)
       cross join pg_catalog.unnest(
         array['INSERT', 'UPDATE', 'DELETE', 'TRUNCATE']
       ) as privilegio(nombre)
       where pg_catalog.has_table_privilege(
         rol.nombre,
         'public.contratos',
         privilegio.nombre
       )
     )
     or exists (
       select 1
       from pg_catalog.unnest(
         array['INSERT', 'UPDATE', 'DELETE', 'TRUNCATE']
       ) as privilegio(nombre)
       where not pg_catalog.has_table_privilege(
         'service_role',
         'public.contratos',
         privilegio.nombre
       )
     )
     or pg_catalog.has_function_privilege(
       'anon',
       'public._sync_contrato_titulares(uuid,jsonb)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticated',
       'public._sync_contrato_titulares(uuid,jsonb)',
       'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'service_role',
       'public._sync_contrato_titulares(uuid,jsonb)',
       'EXECUTE'
     ) then
    raise exception
      'POSTFLIGHT F41-19: DML contractual directo no quedo cerrado';
  end if;
end;
$postflight_acl_contratos$;

do $postflight_acl_hijos_contractuales$
declare
  v_columna text;
  v_privilegio text;
  v_rol text;
begin
  foreach v_rol in array array['anon', 'authenticated'] loop
    foreach v_privilegio in array array['INSERT', 'DELETE', 'TRUNCATE'] loop
      if pg_catalog.has_table_privilege(
        v_rol,
        'public.cronograma_pagos',
        v_privilegio
      ) then
        raise exception
          'POSTFLIGHT F41-20: DML directo de cronograma sigue abierto';
      end if;
    end loop;

    foreach v_privilegio in array array['INSERT', 'UPDATE'] loop
      for v_columna in
        select atributo.attname::text
        from pg_catalog.pg_attribute atributo
        where atributo.attrelid = 'public.contrato_titulares'::regclass
          and atributo.attnum > 0
          and not atributo.attisdropped
      loop
        if pg_catalog.has_column_privilege(
          v_rol,
          'public.contrato_titulares',
          v_columna,
          v_privilegio
        ) then
          raise exception
            'POSTFLIGHT F41-20: DML directo de titulares sigue abierto';
        end if;
      end loop;
    end loop;

    if pg_catalog.has_table_privilege(
         v_rol, 'public.contrato_titulares', 'DELETE'
       )
       or pg_catalog.has_table_privilege(
         v_rol, 'public.contrato_titulares', 'TRUNCATE'
       ) then
      raise exception
        'POSTFLIGHT F41-20: borrado directo de titulares sigue abierto';
    end if;
  end loop;

  foreach v_columna in array array[
    'id',
    'contrato_id',
    'numero_cuota',
    'fecha_programada',
    'monto_programado',
    'creado_en',
    'tipo',
    'notif_pago_enviada_en',
    'recordatorio_3d_enviado_en'
  ] loop
    if pg_catalog.has_column_privilege(
      'authenticated',
      'public.cronograma_pagos',
      v_columna,
      'UPDATE'
    ) then
      raise exception
        'POSTFLIGHT F41-20: termino documental actualizable directo: %',
        v_columna;
    end if;
  end loop;

  foreach v_columna in array array[
    'estado', 'fecha_pago_real', 'monto_pagado', 'registrado_por'
  ] loop
    if not pg_catalog.has_column_privilege(
      'authenticated',
      'public.cronograma_pagos',
      v_columna,
      'UPDATE'
    ) then
      raise exception
        'POSTFLIGHT F41-20: cobro operativo bloqueado: %', v_columna;
    end if;
  end loop;

  foreach v_privilegio in array array[
    'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE'
  ] loop
    if not pg_catalog.has_table_privilege(
      'service_role', 'public.cronograma_pagos', v_privilegio
    ) or not pg_catalog.has_table_privilege(
      'service_role', 'public.contrato_titulares', v_privilegio
    ) then
      raise exception
        'POSTFLIGHT F41-20: backend contractual perdio privilegios';
    end if;
  end loop;
end;
$postflight_acl_hijos_contractuales$;

drop table pg_temp.f41_pdf_writer_oids;
drop table pg_temp.f41_writer_oids;
drop table pg_temp.f41_cronograma_trigger_snapshot;
drop table pg_temp.f41_contrato_pdf_lock_snapshot;
