-- REGISTRO en supabase_migrations.schema_migrations de 20261003162500_crm_base_gestion_seguimiento_activo.
-- `db query --linked --file` NO registra: correr DESPUÉS de aplicar la migración. Idempotente; se niega si
-- los objetos no están, o si la versión ya está registrada con otro nombre u otro contenido.
-- Generado con banco/generar-registrador.py. statements = el archivo entero (md5 705de34645e9fa45266451f8c8f74918).
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_base_gestion_seguimiento_activo_registro'));
do $chk$
begin
  if (
    to_regprocedure('private.trg_leads_guard_seguimiento_activo()') is not null
  ) is not true then
    raise exception 'REGISTRO: la migración 20261003162500 no está aplicada; aplícala primero';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations
             where version = '20261003162500' and (coalesce(name, '') <> 'crm_base_gestion_seguimiento_activo' or statements is distinct from array[$mig$-- 20261003162500_crm_base_gestion_seguimiento_activo.sql
--
-- Base para gestión del analista · B6: a un lead descartado que su analista está trabajando nadie le cambia el responsable.
-- Miguel (02/10/2026): «evitar que un supervisor reasigne un lead que está siendo trabajado por el analista». Respuestas
-- (03/10): (1) la rellamada agendada vigente TAMBIÉN cuenta; (2) en el Centro de rescate se ve EN GRIS «En gestión por X
-- hasta el día Y», sin poder elegirlo; (3) el candado va en el LEAD, para toda vía: el auditor-rls probó que la ficha
-- (PATCH de vendedor_id) y «tomar lead libre» también movían el lead. Plan aprobado por Miguel el 03/10/2026.
--
-- QUÉ:
--   · NUEVA `private.base_gestion_en_gestion_hasta(uuid)` — la regla, en un solo sitio: último intento de la base del ciclo vigente + 7 días, o la
--     rellamada agendada en ese ciclo; NULL si el dueño ya no está activo (una baja lo libera).
--   · NUEVO trigger `trg_leads_00_seguimiento_activo` (BEFORE UPDATE de crm.leads, WHEN el lead está descartado y cambia su
--     vendedor_id) con `private.trg_leads_guard_seguimiento_activo()` (DEFINER: llama a la ayudante privada): P0409, detail `estado=en_gestion`. Cubre el
--     reparto del rescate (todo el lote falla: corre dentro de su transacción), la ficha y «tomar lead libre».
--   · `crm.rescate_descartes_mes(date)` — drop + create (cambia el `returns table`): `en_gestion_por` y `en_gestion_hasta` al final;
--     `puede_rescatar` = false mientras dure. `estado` NO cambia: el bundle viejo valida una lista cerrada.
--   `crm.rescatar_descartes` NO se toca (está declarada con su huella en el censo analítico: cambiarla la caducaría).
-- PRECONDICIÓN: B3c y B5 aplicadas; cuerpo vivo de rescate_descartes_mes medido en producción el 03/10 (md5 7c6363fb…,
-- de una migración que no está en el repo: su origen consta en el ledger).
--
-- REVERSA: `supabase/scripts/base-gestion/reversa-seguimiento-activo.sql` (quita el trigger, reinstala el cuerpo vivo de
-- rescate_descartes_mes y borra las dos funciones). No toca datos.
begin;
set local lock_timeout = '10s';
set local statement_timeout = '60s';
set local search_path = '';
set local quote_all_identifiers = off;

do $preflight$
begin
  if (
    (select md5(p.prosrc) = '7c6363fbc96bc51f14997196e6eb8661' and p.proacl::text = '{postgres=X/postgres,authenticated=X/postgres}' from pg_proc p where p.oid = to_regprocedure('crm.rescate_descartes_mes(date)'))
    and (select md5(p.prosrc) = 'b2629fba517938457b64cdbc5856ee82' from pg_proc p where p.oid = to_regprocedure('crm.obtener_base_gestion(uuid)'))
    and to_regprocedure('private.base_gestion_en_gestion_hasta(uuid)') is null
    and to_regprocedure('private.trg_leads_guard_seguimiento_activo()') is null
    and not exists (select 1 from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_00_seguimiento_activo')
  ) is not true then
    raise exception 'PREFLIGHT: falta B3c/B5, el cuerpo vivo del rescate no es el medido el 03/10 o B6 ya esta aplicada';
  end if;
end;
$preflight$;

create temp table _b6_censo_antes on commit drop as select c.objeto from private.contadores_crudos_leads_citas() c;

-- ── La regla ─────────────────────────────────────────────────────────────────────────────────────────────────
create function private.base_gestion_en_gestion_hasta(p_lead_id uuid)
returns date
language sql stable security invoker set search_path = '' as $$
  -- Hasta qué día (Lima) el lead descartado sigue en gestión de su analista: el último intento de la base del ciclo vigente
  -- (desde descartado_en) + 7 días, o el día de la rellamada agendada en ese ciclo, lo que llegue más lejos. NULL si ya no
  -- está en gestión, si no está descartado o si su dueño ya no está activo (una baja libera sus leads).
  select case when x.hasta >= (pg_catalog.now() at time zone 'America/Lima')::date then x.hasta end
    from (
      select greatest(
               (i.ultimo at time zone 'America/Lima')::date + 7,
               -- La rellamada solo cuenta si la agendó un intento de ESTE ciclo (una de un ciclo anterior no bloquea).
               case when i.ultimo is not null then (l.proxima_llamada_en at time zone 'America/Lima')::date end) as hasta
        from crm.leads l
        cross join lateral (
          select max(a.creado_en) as ultimo
            from crm.actividades a
           where a.lead_id = l.id
             and a.metadata->>'evento' = 'intento_base'
             and a.creado_en >= l.descartado_en
        ) i
       where l.id = p_lead_id
         and l.etapa = 'descartado'
         and exists (select 1 from crm.equipo e join public.perfiles p on p.id = e.perfil_id
                      where e.perfil_id = l.vendedor_id and e.activo and p.activo)
    ) x
$$;
alter function private.base_gestion_en_gestion_hasta(uuid) owner to postgres;
revoke all on function private.base_gestion_en_gestion_hasta(uuid) from public, anon, authenticated, service_role;
comment on function private.base_gestion_en_gestion_hasta(uuid) is
  'B6 (Miguel, 03/10/2026): seguimiento activo de un lead descartado. Último día (Lima) en que sigue en gestión de su analista: último intento de la base del ciclo vigente (desde descartado_en) + 7 días, o el día de la rellamada agendada en ese ciclo, el mayor. NULL si no hay seguimiento activo, si el lead no está descartado o si su dueño ya no está activo. Fuente única del candado (trg_leads_00_seguimiento_activo) y del gris del Centro de rescate. INVOKER, sin EXECUTE para roles de la API.';

-- ── El candado, en el lead ───────────────────────────────────────────────────────────────────────────────────
create function private.trg_leads_guard_seguimiento_activo()
returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_hasta date;
begin
  -- B6 (Miguel, 03/10/2026): a un lead descartado que su analista está trabajando nadie le cambia el responsable, venga por
  -- el Centro de rescate, la ficha o «tomar lead libre». Una baja (dueño inactivo) lo libera: la ayudante devuelve NULL.
  v_hasta := private.base_gestion_en_gestion_hasta(old.id);
  if v_hasta is not null then
    -- Sin nombres ni identificadores (Codex 03/10): quien lo intenta por «tomar lead libre» puede no ver al lead ni a su
    -- analista; el detail solo dice el estado y la fecha.
    raise exception 'Este lead lo está trabajando su analista hasta el %: no se le puede cambiar el responsable',
      pg_catalog.to_char(v_hasta, 'DD/MM/YYYY')
      using errcode = 'P0409',
            detail = pg_catalog.jsonb_build_object('estado', 'en_gestion', 'hasta', v_hasta)::text;
  end if;
  return new;
end;
$$;
alter function private.trg_leads_guard_seguimiento_activo() owner to postgres;
revoke all on function private.trg_leads_guard_seguimiento_activo() from public, anon, authenticated, service_role;
comment on function private.trg_leads_guard_seguimiento_activo() is
  'B6 (Miguel, 03/10/2026): candado de seguimiento activo. Rechaza (P0409, detail estado=en_gestion y hasta, sin identificadores) cambiar el responsable de un lead descartado mientras su analista lo trabaja, por cualquier vía. DEFINER: llama a private.base_gestion_en_gestion_hasta, que ningún rol de la API puede ejecutar; search_path vacío y nombres calificados. El mensaje y el detail no nombran ni identifican al lead ni al analista.';
create trigger trg_leads_00_seguimiento_activo
  before update on crm.leads
  for each row
  when (old.etapa = 'descartado' and new.vendedor_id is distinct from old.vendedor_id)
  execute function private.trg_leads_guard_seguimiento_activo();
comment on trigger trg_leads_00_seguimiento_activo on crm.leads is
  'B6 (03/10/2026): un lead descartado en gestión de su analista no cambia de responsable (rescate, ficha, tomar lead libre). Ver private.trg_leads_guard_seguimiento_activo.';

-- ── El gris del Centro de rescate ────────────────────────────────────────────────────────────────────────────
drop function crm.rescate_descartes_mes(date);
create function crm.rescate_descartes_mes(p_mes date)
 RETURNS TABLE(episodio_id uuid, lead_id uuid, nombre_completo text, distrito text, origen text, categoria_interes text, monto_estimado numeric, moneda text, motivo_descarte text, descartado_en timestamp with time zone, asesor_id uuid, asesor_nombre text, puede_rescatar boolean, estado text, en_gestion_por text, en_gestion_hasta date)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := (select auth.uid());
  v_rol text;
  v_mes date := pg_catalog.date_trunc('month', p_mes)::date;
begin
  if p_mes is null then
    raise exception 'El mes es obligatorio' using errcode = '22023';
  end if;

  select e.rol_crm
    into v_rol
  from crm.equipo e
  join public.perfiles p on p.id = e.perfil_id
  where e.perfil_id = v_actor
    and e.activo = true
    and p.activo = true
    and e.rol_crm in ('supervisor', 'gerencia');

  if v_actor is null or v_rol is null then
    raise exception 'Solo supervisión puede consultar Base para gestión'
      using errcode = '42501';
  end if;

  return query
  select
    la.id as episodio_id,
    l.id as lead_id,
    l.nombre_completo,
    l.distrito,
    la.origen,
    la.categoria_interes,
    la.monto_estimado,
    la.moneda,
    la.motivo_descarte_cierre,
    la.resultado_en,
    la.analista_id,
    p_asesor.nombre_completo,
    (
      l.activo = true
      and l.etapa = 'descartado'
      and l.descartado_en is not distinct from la.resultado_en
      and la.motivo_descarte_cierre <> 'datos_invalidos'
      and l.no_contactar is not true
      and g.hasta is null  -- B6: con seguimiento activo del analista no se puede elegir
    ) as puede_rescatar,
    case
      when l.activo = true
       and l.etapa = 'descartado'
       and l.descartado_en is not distinct from la.resultado_en
       and la.motivo_descarte_cierre <> 'datos_invalidos'
       and l.no_contactar is not true
        then 'pendiente'
      when exists (
        select 1
        from crm.lead_asignaciones la_posterior
        where la_posterior.lead_id = la.lead_id
          and la_posterior.asignado_en > la.resultado_en
      ) then 'rescatado'
      else 'historial'
    end as estado,
    p_gestiona.nombre_completo as en_gestion_por,
    g.hasta as en_gestion_hasta
  from crm.lead_asignaciones la
  join crm.leads l on l.id = la.lead_id
  join public.perfiles p_asesor on p_asesor.id = la.analista_id
  -- B6 (Miguel, 03/10/2026): seguimiento activo SOLO de los episodios que hoy se podrían rescatar (los demás son historial).
  left join lateral (
    select private.base_gestion_en_gestion_hasta(l.id) as hasta
     where l.activo = true
       and l.etapa = 'descartado'
       and l.descartado_en is not distinct from la.resultado_en
       and la.motivo_descarte_cierre <> 'datos_invalidos'
       and l.no_contactar is not true
  ) g on true
  left join public.perfiles p_gestiona on p_gestiona.id = l.vendedor_id and g.hasta is not null
  where la.resultado = 'descartado'
    and la.resultado_en is not null
    and la.resultado_en >= (v_mes::timestamp at time zone 'America/Lima')
    and la.resultado_en < ((v_mes + interval '1 month')::timestamp at time zone 'America/Lima')
    and (
      v_rol = 'gerencia'
      or la.analista_id in (
        select private.vendedor_ids_visibles(v_actor)
      )
    )
  order by la.resultado_en desc, la.id desc;
end;
$function$;
alter function crm.rescate_descartes_mes(date) owner to postgres;
revoke all on function crm.rescate_descartes_mes(date) from public, anon, authenticated, service_role;
grant execute on function crm.rescate_descartes_mes(date) to authenticated;
comment on function crm.rescate_descartes_mes(date) is 'Historial mensual sin PII de contacto para Base para gestión. Cada fila es un episodio inmutable del ledger, no el estado actual mutable del lead. B6 (03/10/2026): en_gestion_por y en_gestion_hasta marcan el seguimiento activo del analista (intento de la base hace 7 días o menos, o rellamada vigente de ese ciclo); mientras dure, puede_rescatar = false y la pantalla lo pinta en gris. estado no cambia (el bundle viejo valida una lista cerrada).';

do $postflight$
begin
  if (
    (select md5(p.prosrc) = 'af0701a9e095e1004a64b7e289789d7c' and not p.prosecdef and p.provolatile = 's' and p.proowner = 'postgres'::regrole
        and p.proconfig = array['search_path=""']::text[] and p.proacl::text = '{postgres=X/postgres}'
       from pg_proc p where p.oid = to_regprocedure('private.base_gestion_en_gestion_hasta(uuid)'))
    and (select md5(p.prosrc) = 'dbdc8740d9f68a523e7b5afb54d2d774' and p.prosecdef and p.proowner = 'postgres'::regrole
        and p.proconfig = array['search_path=""']::text[] and p.proacl::text = '{postgres=X/postgres}'
       from pg_proc p where p.oid = to_regprocedure('private.trg_leads_guard_seguimiento_activo()'))
    and (select md5(pg_get_triggerdef(t.oid)) = '7b08e2d83b66027e850035687ed07feb' and t.tgenabled = 'O'
       from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_00_seguimiento_activo')
    and (select md5(p.prosrc) = 'd21ca8325c777fb207d5f58df751748f' and p.proargnames[pg_catalog.array_length(p.proargnames, 1)] = 'en_gestion_hasta'
        and p.prosecdef and p.proowner = 'postgres'::regrole and p.proconfig = array['search_path=""']::text[]
        and p.proacl::text = '{postgres=X/postgres,authenticated=X/postgres}'
       from pg_proc p where p.oid = to_regprocedure('crm.rescate_descartes_mes(date)'))
    and (select md5(p.prosrc) = '5f4f5ca115f535f6ab8a1209dda19a0f' from pg_proc p where p.oid = to_regprocedure('crm.rescatar_descartes(uuid[],uuid[],boolean)'))
    -- B6 no mueve el censo analítico (ninguna de sus piezas cuenta):
    and not exists (select 1 from private.contadores_crudos_leads_citas() c where c.objeto not in (select a.objeto from pg_temp._b6_censo_antes a))
    and (select count(*) from pg_temp._b6_censo_antes) = (select count(*) from private.contadores_crudos_leads_citas())
  ) is not true then
    raise exception 'POSTFLIGHT: la regla, el candado o el gris no quedaron como se esperaba, o el censo cambio';
  end if;
  raise notice 'base_gestion_seguimiento_activo OK: regla única, candado en el lead para toda vía, gris en el rescate, censo intacto';
end;
$postflight$;
notify pgrst, 'reload schema';
commit;
$mig$])) then
    raise exception 'REGISTRO: la versión 20261003162500 ya está registrada con otro nombre o contenido';
  end if;
end $chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20261003162500', 'crm_base_gestion_seguimiento_activo', array[$mig$-- 20261003162500_crm_base_gestion_seguimiento_activo.sql
--
-- Base para gestión del analista · B6: a un lead descartado que su analista está trabajando nadie le cambia el responsable.
-- Miguel (02/10/2026): «evitar que un supervisor reasigne un lead que está siendo trabajado por el analista». Respuestas
-- (03/10): (1) la rellamada agendada vigente TAMBIÉN cuenta; (2) en el Centro de rescate se ve EN GRIS «En gestión por X
-- hasta el día Y», sin poder elegirlo; (3) el candado va en el LEAD, para toda vía: el auditor-rls probó que la ficha
-- (PATCH de vendedor_id) y «tomar lead libre» también movían el lead. Plan aprobado por Miguel el 03/10/2026.
--
-- QUÉ:
--   · NUEVA `private.base_gestion_en_gestion_hasta(uuid)` — la regla, en un solo sitio: último intento de la base del ciclo vigente + 7 días, o la
--     rellamada agendada en ese ciclo; NULL si el dueño ya no está activo (una baja lo libera).
--   · NUEVO trigger `trg_leads_00_seguimiento_activo` (BEFORE UPDATE de crm.leads, WHEN el lead está descartado y cambia su
--     vendedor_id) con `private.trg_leads_guard_seguimiento_activo()` (DEFINER: llama a la ayudante privada): P0409, detail `estado=en_gestion`. Cubre el
--     reparto del rescate (todo el lote falla: corre dentro de su transacción), la ficha y «tomar lead libre».
--   · `crm.rescate_descartes_mes(date)` — drop + create (cambia el `returns table`): `en_gestion_por` y `en_gestion_hasta` al final;
--     `puede_rescatar` = false mientras dure. `estado` NO cambia: el bundle viejo valida una lista cerrada.
--   `crm.rescatar_descartes` NO se toca (está declarada con su huella en el censo analítico: cambiarla la caducaría).
-- PRECONDICIÓN: B3c y B5 aplicadas; cuerpo vivo de rescate_descartes_mes medido en producción el 03/10 (md5 7c6363fb…,
-- de una migración que no está en el repo: su origen consta en el ledger).
--
-- REVERSA: `supabase/scripts/base-gestion/reversa-seguimiento-activo.sql` (quita el trigger, reinstala el cuerpo vivo de
-- rescate_descartes_mes y borra las dos funciones). No toca datos.
begin;
set local lock_timeout = '10s';
set local statement_timeout = '60s';
set local search_path = '';
set local quote_all_identifiers = off;

do $preflight$
begin
  if (
    (select md5(p.prosrc) = '7c6363fbc96bc51f14997196e6eb8661' and p.proacl::text = '{postgres=X/postgres,authenticated=X/postgres}' from pg_proc p where p.oid = to_regprocedure('crm.rescate_descartes_mes(date)'))
    and (select md5(p.prosrc) = 'b2629fba517938457b64cdbc5856ee82' from pg_proc p where p.oid = to_regprocedure('crm.obtener_base_gestion(uuid)'))
    and to_regprocedure('private.base_gestion_en_gestion_hasta(uuid)') is null
    and to_regprocedure('private.trg_leads_guard_seguimiento_activo()') is null
    and not exists (select 1 from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_00_seguimiento_activo')
  ) is not true then
    raise exception 'PREFLIGHT: falta B3c/B5, el cuerpo vivo del rescate no es el medido el 03/10 o B6 ya esta aplicada';
  end if;
end;
$preflight$;

create temp table _b6_censo_antes on commit drop as select c.objeto from private.contadores_crudos_leads_citas() c;

-- ── La regla ─────────────────────────────────────────────────────────────────────────────────────────────────
create function private.base_gestion_en_gestion_hasta(p_lead_id uuid)
returns date
language sql stable security invoker set search_path = '' as $$
  -- Hasta qué día (Lima) el lead descartado sigue en gestión de su analista: el último intento de la base del ciclo vigente
  -- (desde descartado_en) + 7 días, o el día de la rellamada agendada en ese ciclo, lo que llegue más lejos. NULL si ya no
  -- está en gestión, si no está descartado o si su dueño ya no está activo (una baja libera sus leads).
  select case when x.hasta >= (pg_catalog.now() at time zone 'America/Lima')::date then x.hasta end
    from (
      select greatest(
               (i.ultimo at time zone 'America/Lima')::date + 7,
               -- La rellamada solo cuenta si la agendó un intento de ESTE ciclo (una de un ciclo anterior no bloquea).
               case when i.ultimo is not null then (l.proxima_llamada_en at time zone 'America/Lima')::date end) as hasta
        from crm.leads l
        cross join lateral (
          select max(a.creado_en) as ultimo
            from crm.actividades a
           where a.lead_id = l.id
             and a.metadata->>'evento' = 'intento_base'
             and a.creado_en >= l.descartado_en
        ) i
       where l.id = p_lead_id
         and l.etapa = 'descartado'
         and exists (select 1 from crm.equipo e join public.perfiles p on p.id = e.perfil_id
                      where e.perfil_id = l.vendedor_id and e.activo and p.activo)
    ) x
$$;
alter function private.base_gestion_en_gestion_hasta(uuid) owner to postgres;
revoke all on function private.base_gestion_en_gestion_hasta(uuid) from public, anon, authenticated, service_role;
comment on function private.base_gestion_en_gestion_hasta(uuid) is
  'B6 (Miguel, 03/10/2026): seguimiento activo de un lead descartado. Último día (Lima) en que sigue en gestión de su analista: último intento de la base del ciclo vigente (desde descartado_en) + 7 días, o el día de la rellamada agendada en ese ciclo, el mayor. NULL si no hay seguimiento activo, si el lead no está descartado o si su dueño ya no está activo. Fuente única del candado (trg_leads_00_seguimiento_activo) y del gris del Centro de rescate. INVOKER, sin EXECUTE para roles de la API.';

-- ── El candado, en el lead ───────────────────────────────────────────────────────────────────────────────────
create function private.trg_leads_guard_seguimiento_activo()
returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_hasta date;
begin
  -- B6 (Miguel, 03/10/2026): a un lead descartado que su analista está trabajando nadie le cambia el responsable, venga por
  -- el Centro de rescate, la ficha o «tomar lead libre». Una baja (dueño inactivo) lo libera: la ayudante devuelve NULL.
  v_hasta := private.base_gestion_en_gestion_hasta(old.id);
  if v_hasta is not null then
    -- Sin nombres ni identificadores (Codex 03/10): quien lo intenta por «tomar lead libre» puede no ver al lead ni a su
    -- analista; el detail solo dice el estado y la fecha.
    raise exception 'Este lead lo está trabajando su analista hasta el %: no se le puede cambiar el responsable',
      pg_catalog.to_char(v_hasta, 'DD/MM/YYYY')
      using errcode = 'P0409',
            detail = pg_catalog.jsonb_build_object('estado', 'en_gestion', 'hasta', v_hasta)::text;
  end if;
  return new;
end;
$$;
alter function private.trg_leads_guard_seguimiento_activo() owner to postgres;
revoke all on function private.trg_leads_guard_seguimiento_activo() from public, anon, authenticated, service_role;
comment on function private.trg_leads_guard_seguimiento_activo() is
  'B6 (Miguel, 03/10/2026): candado de seguimiento activo. Rechaza (P0409, detail estado=en_gestion y hasta, sin identificadores) cambiar el responsable de un lead descartado mientras su analista lo trabaja, por cualquier vía. DEFINER: llama a private.base_gestion_en_gestion_hasta, que ningún rol de la API puede ejecutar; search_path vacío y nombres calificados. El mensaje y el detail no nombran ni identifican al lead ni al analista.';
create trigger trg_leads_00_seguimiento_activo
  before update on crm.leads
  for each row
  when (old.etapa = 'descartado' and new.vendedor_id is distinct from old.vendedor_id)
  execute function private.trg_leads_guard_seguimiento_activo();
comment on trigger trg_leads_00_seguimiento_activo on crm.leads is
  'B6 (03/10/2026): un lead descartado en gestión de su analista no cambia de responsable (rescate, ficha, tomar lead libre). Ver private.trg_leads_guard_seguimiento_activo.';

-- ── El gris del Centro de rescate ────────────────────────────────────────────────────────────────────────────
drop function crm.rescate_descartes_mes(date);
create function crm.rescate_descartes_mes(p_mes date)
 RETURNS TABLE(episodio_id uuid, lead_id uuid, nombre_completo text, distrito text, origen text, categoria_interes text, monto_estimado numeric, moneda text, motivo_descarte text, descartado_en timestamp with time zone, asesor_id uuid, asesor_nombre text, puede_rescatar boolean, estado text, en_gestion_por text, en_gestion_hasta date)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := (select auth.uid());
  v_rol text;
  v_mes date := pg_catalog.date_trunc('month', p_mes)::date;
begin
  if p_mes is null then
    raise exception 'El mes es obligatorio' using errcode = '22023';
  end if;

  select e.rol_crm
    into v_rol
  from crm.equipo e
  join public.perfiles p on p.id = e.perfil_id
  where e.perfil_id = v_actor
    and e.activo = true
    and p.activo = true
    and e.rol_crm in ('supervisor', 'gerencia');

  if v_actor is null or v_rol is null then
    raise exception 'Solo supervisión puede consultar Base para gestión'
      using errcode = '42501';
  end if;

  return query
  select
    la.id as episodio_id,
    l.id as lead_id,
    l.nombre_completo,
    l.distrito,
    la.origen,
    la.categoria_interes,
    la.monto_estimado,
    la.moneda,
    la.motivo_descarte_cierre,
    la.resultado_en,
    la.analista_id,
    p_asesor.nombre_completo,
    (
      l.activo = true
      and l.etapa = 'descartado'
      and l.descartado_en is not distinct from la.resultado_en
      and la.motivo_descarte_cierre <> 'datos_invalidos'
      and l.no_contactar is not true
      and g.hasta is null  -- B6: con seguimiento activo del analista no se puede elegir
    ) as puede_rescatar,
    case
      when l.activo = true
       and l.etapa = 'descartado'
       and l.descartado_en is not distinct from la.resultado_en
       and la.motivo_descarte_cierre <> 'datos_invalidos'
       and l.no_contactar is not true
        then 'pendiente'
      when exists (
        select 1
        from crm.lead_asignaciones la_posterior
        where la_posterior.lead_id = la.lead_id
          and la_posterior.asignado_en > la.resultado_en
      ) then 'rescatado'
      else 'historial'
    end as estado,
    p_gestiona.nombre_completo as en_gestion_por,
    g.hasta as en_gestion_hasta
  from crm.lead_asignaciones la
  join crm.leads l on l.id = la.lead_id
  join public.perfiles p_asesor on p_asesor.id = la.analista_id
  -- B6 (Miguel, 03/10/2026): seguimiento activo SOLO de los episodios que hoy se podrían rescatar (los demás son historial).
  left join lateral (
    select private.base_gestion_en_gestion_hasta(l.id) as hasta
     where l.activo = true
       and l.etapa = 'descartado'
       and l.descartado_en is not distinct from la.resultado_en
       and la.motivo_descarte_cierre <> 'datos_invalidos'
       and l.no_contactar is not true
  ) g on true
  left join public.perfiles p_gestiona on p_gestiona.id = l.vendedor_id and g.hasta is not null
  where la.resultado = 'descartado'
    and la.resultado_en is not null
    and la.resultado_en >= (v_mes::timestamp at time zone 'America/Lima')
    and la.resultado_en < ((v_mes + interval '1 month')::timestamp at time zone 'America/Lima')
    and (
      v_rol = 'gerencia'
      or la.analista_id in (
        select private.vendedor_ids_visibles(v_actor)
      )
    )
  order by la.resultado_en desc, la.id desc;
end;
$function$;
alter function crm.rescate_descartes_mes(date) owner to postgres;
revoke all on function crm.rescate_descartes_mes(date) from public, anon, authenticated, service_role;
grant execute on function crm.rescate_descartes_mes(date) to authenticated;
comment on function crm.rescate_descartes_mes(date) is 'Historial mensual sin PII de contacto para Base para gestión. Cada fila es un episodio inmutable del ledger, no el estado actual mutable del lead. B6 (03/10/2026): en_gestion_por y en_gestion_hasta marcan el seguimiento activo del analista (intento de la base hace 7 días o menos, o rellamada vigente de ese ciclo); mientras dure, puede_rescatar = false y la pantalla lo pinta en gris. estado no cambia (el bundle viejo valida una lista cerrada).';

do $postflight$
begin
  if (
    (select md5(p.prosrc) = 'af0701a9e095e1004a64b7e289789d7c' and not p.prosecdef and p.provolatile = 's' and p.proowner = 'postgres'::regrole
        and p.proconfig = array['search_path=""']::text[] and p.proacl::text = '{postgres=X/postgres}'
       from pg_proc p where p.oid = to_regprocedure('private.base_gestion_en_gestion_hasta(uuid)'))
    and (select md5(p.prosrc) = 'dbdc8740d9f68a523e7b5afb54d2d774' and p.prosecdef and p.proowner = 'postgres'::regrole
        and p.proconfig = array['search_path=""']::text[] and p.proacl::text = '{postgres=X/postgres}'
       from pg_proc p where p.oid = to_regprocedure('private.trg_leads_guard_seguimiento_activo()'))
    and (select md5(pg_get_triggerdef(t.oid)) = '7b08e2d83b66027e850035687ed07feb' and t.tgenabled = 'O'
       from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_00_seguimiento_activo')
    and (select md5(p.prosrc) = 'd21ca8325c777fb207d5f58df751748f' and p.proargnames[pg_catalog.array_length(p.proargnames, 1)] = 'en_gestion_hasta'
        and p.prosecdef and p.proowner = 'postgres'::regrole and p.proconfig = array['search_path=""']::text[]
        and p.proacl::text = '{postgres=X/postgres,authenticated=X/postgres}'
       from pg_proc p where p.oid = to_regprocedure('crm.rescate_descartes_mes(date)'))
    and (select md5(p.prosrc) = '5f4f5ca115f535f6ab8a1209dda19a0f' from pg_proc p where p.oid = to_regprocedure('crm.rescatar_descartes(uuid[],uuid[],boolean)'))
    -- B6 no mueve el censo analítico (ninguna de sus piezas cuenta):
    and not exists (select 1 from private.contadores_crudos_leads_citas() c where c.objeto not in (select a.objeto from pg_temp._b6_censo_antes a))
    and (select count(*) from pg_temp._b6_censo_antes) = (select count(*) from private.contadores_crudos_leads_citas())
  ) is not true then
    raise exception 'POSTFLIGHT: la regla, el candado o el gris no quedaron como se esperaba, o el censo cambio';
  end if;
  raise notice 'base_gestion_seguimiento_activo OK: regla única, candado en el lead para toda vía, gris en el rescate, censo intacto';
end;
$postflight$;
notify pgrst, 'reload schema';
commit;
$mig$])
on conflict (version) do nothing;
do $post$
begin
  if not exists (select 1 from supabase_migrations.schema_migrations
                 where version = '20261003162500' and name = 'crm_base_gestion_seguimiento_activo' and cardinality(statements) = 1
                   and md5(statements[1]) = '705de34645e9fa45266451f8c8f74918') then
    raise exception 'REGISTRO: la fila 20261003162500 / crm_base_gestion_seguimiento_activo no quedó como se esperaba';
  end if;
  raise notice 'REGISTRO: 20261003162500 / crm_base_gestion_seguimiento_activo (1 sentencia: el archivo entero)';
end $post$;
commit;
