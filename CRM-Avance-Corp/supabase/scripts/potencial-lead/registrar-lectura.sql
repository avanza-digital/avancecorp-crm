-- REGISTRO en supabase_migrations.schema_migrations de 20261001151704_crm_potencial_lead_lectura.
-- `db query --linked --file` NO registra: correr DESPUÉS de aplicar la migración. Idempotente; se niega si
-- los objetos no están, o si la versión ya está registrada con otro nombre u otro contenido.
-- Generado con banco/generar-registrador.py. statements = el archivo entero (md5 7c2b85345ddd32e16430c88639628fc2).
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_potencial_lead_lectura_registro'));
do $chk$
begin
  if (
    to_regprocedure('crm.potencial_leads_fn(uuid[])') is not null
    and to_regprocedure('private.potencial_lectura(uuid,uuid[],date,timestamp with time zone,date)') is not null
    and to_regprocedure('private.potencial_proxima_baja(crm.nivel_potencial,date,date)') is not null
    and to_regprocedure('private.potencial_proxima_corrida(timestamp with time zone)') is not null
  ) is not true then
    raise exception 'REGISTRO: la migración 20261001151704 no está aplicada; aplícala primero';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations
             where version = '20261001151704' and (coalesce(name, '') <> 'crm_potencial_lead_lectura' or statements is distinct from array[$mig$-- 20261001151704_crm_potencial_lead_lectura.sql
--
-- Potencial del lead · FASE 3, entrega A (servidor): la puerta de LECTURA. Plan aprobado por
-- Miguel el 01/10/2026 («vamos dale» al plan en dos entregas: A marcar y ver, B filtrar). Nota
-- del vault: «Potencial del lead - Frio Tibio Estrella (2026-09-30)», «Fase 3 · mapa y plan».
--
-- QUÉ HACE
--   · private.potencial_proxima_corrida(instante): la fecha (Lima) de la próxima pasada de la tarea
--     de la fase 2, por su HORARIO NOMINAL (no mira si la pasada ya corrió). La tarea se programa a
--     las 05:10 y 05:40 Lima: hasta las 05:45 se responde «hoy» (cinco minutos de margen para que la
--     última pasada arranque y termine; dura menos de un segundo); desde las 05:45, «mañana». El
--     postflight comprueba que el job sigue teniendo ese horario, ese comando y ese destino.
--   · private.potencial_proxima_baja(nivel, día del reloj, desde): la primera fecha, desde la
--     próxima corrida, en que la regla de la fase 2 da un nivel menor, y ese nivel. Bucle que para
--     en la primera (no recorre fechas de más) y no hace nada con un nivel que nunca baja.
--   · private.potencial_lectura(actor, lead_ids, hoy, corte, próxima corrida): por cada lead
--     pedido que el actor PUEDE VER (espejo de la policy leads_select), la marca vigente y lo que
--     la pantalla tiene que decir: nivel, origen (manual | caducidad), el último nivel que puso una
--     PERSONA, cuándo se marcó, los días completos sin gestión (lunes a sábado), a qué nivel
--     bajará y en qué madrugada si nadie gestiona, y si el actor puede marcarlo. Un lead visible
--     sin marca viaja con nivel null. UNA sola regla: los días salen de private.potencial_reloj y
--     private.dias_lunes_a_sabado, el nivel siguiente de private.potencial_nivel_tras (fase 2), y
--     el permiso de private.potencial_rechazo (la misma función que decide en la puerta de
--     marcar, fase 1). Recibe hoy, el corte y la próxima corrida para ensayarse con calendario.
--     El actor DEBE ser el de la sesión (Codex f3a r1): con otro, 42501.
--   · crm.potencial_leads_fn(uuid[]): la puerta. Sesión, el gate restrictivo del CRM
--     (private.puede_acceder_crm, invocado y no copiado), tope de 200 ids y la bandera
--     'potencial_lead': apagada devuelve {version:1, habilitada:false, items:[]} SIN leer nada;
--     encendida, {version:1, habilitada:true, items:[…]}.
-- QUÉ SIGNIFICA baja_el (Codex f3a r1 y r2): la primera madrugada, contando desde el siguiente
--   horario NOMINAL de la tarea, en que la regla la bajaría con lo que se sabe AHORA. No es una
--   promesa ni acredita ejecución: un contacto o una marca nuevos la aplazan; si el lead está ocupado
--   o la pasada llega a su límite de 200, la bajada queda para la pasada siguiente; y si pg_cron se
--   retrasa más allá de las 05:45, una pasada de hoy todavía puede bajarla hoy. La pantalla lo dice
--   siempre en condicional («si no se gestiona»).
-- NO TOCA nada de lo existente: ninguna puerta de cartera, cola, SLA ni Gestión Diaria cambia. La
--   pantalla une la marca por lead_id, igual que hace con crm.cierres_estado_fn.
-- CAPAS: puerta crm (valida, autoriza, delega) → núcleo private (INVOKER, sin EXECUTE para la
--   API) → tablas (crm.lead_potencial y su historial, sin grants para la API).
-- SECURITY DEFINER, justificación: las tablas de la marca no tienen grants para la API (fase 1,
--   auditor-rls r1) y el reloj y la regla de la fase 2 no tienen EXECUTE para la API: una puerta
--   INVOKER no puede leerlos. Molde: crm.cierres_estado_fn. La visibilidad se verifica de forma
--   explícita con el ESPEJO de leads_select; el preflight fija por md5 esa policy, el gate
--   restrictivo de crm.leads y los ayudantes en que se apoyan: si alguno cambió desde el ensayo en
--   el banco, la migración se niega y hay que volver a revisarla.
-- SIN contar: private.contadores_crudos_leads_citas vigila toda función que nombre crm.leads y
--   use un agregado de conteo; aquí no hay ninguno (jsonb_agg y cardinality).
-- REVERSA: supabase/scripts/potencial-lead/reversa-lectura.sql (quita las dos funciones; no hay
--   datos que perder).

begin;
set local lock_timeout = '5s';

-- ── 0 · Preflight ──────────────────────────────────────────────────────────────
do $preflight$
declare
  v_huellas text;
  v_policies text;
begin
  -- Texto de catálogo independiente de la sesión: todo calificado y sin comillas forzadas
  -- (quote_all_identifiers cambiaría el texto de pg_get_expr y con él las huellas; Codex f3a r1).
  perform pg_catalog.set_config('search_path', '', true);
  perform pg_catalog.set_config('quote_all_identifiers', 'off', true);

  if (
    pg_catalog.to_regclass('crm.lead_potencial') is not null
    and pg_catalog.to_regclass('crm.lead_potencial_eventos') is not null
    and pg_catalog.to_regprocedure('private.potencial_rechazo(uuid,uuid)') is not null
    and pg_catalog.to_regprocedure('private.potencial_reloj(uuid,timestamp with time zone,timestamp with time zone)') is not null
    and pg_catalog.to_regprocedure('private.dias_lunes_a_sabado(date,date)') is not null
    and pg_catalog.to_regprocedure('private.potencial_nivel_tras(crm.nivel_potencial,integer)') is not null
    and exists (select 1 from crm.multiempresa_flags f where f.nombre = 'potencial_lead')
  ) is not true then
    raise exception 'PREFLIGHT potencial_lectura: faltan la fase 1 (20260930213647) o la fase 2 (20260930235917)';
  end if;

  if (
    not exists (
      select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
      where (n.nspname = 'crm' and p.proname = 'potencial_leads_fn')
         or (n.nspname = 'private' and p.proname in ('potencial_lectura', 'potencial_proxima_baja', 'potencial_proxima_corrida')))
  ) is not true then
    raise exception 'PREFLIGHT potencial_lectura: ya aplicada o aplicada a medias';
  end if;

  -- La visibilidad de la puerta descansa en estos ayudantes: identidad por cuerpo + DEFINER +
  -- volatilidad + configuración + dueño (pg_get_functiondef no sirve: cambia con la sesión).
  select pg_catalog.string_agg(
           p.oid::pg_catalog.regprocedure::text || '=' ||
           pg_catalog.md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|'
                          || coalesce(pg_catalog.array_to_string(p.proconfig, ','), '') || '|' || p.proowner::pg_catalog.regrole::text),
           ' ' order by p.oid::pg_catalog.regprocedure::text)
    into v_huellas
  from pg_catalog.pg_proc p
  where p.oid in (pg_catalog.to_regprocedure('private.rol_crm(uuid)'),
                  pg_catalog.to_regprocedure('private.vendedor_ids_visibles(uuid)'),
                  pg_catalog.to_regprocedure('private.es_lector_global()'),
                  pg_catalog.to_regprocedure('private.puede_acceder_crm()'),
                  pg_catalog.to_regprocedure('crm.bandera_activa(text)'),
                  pg_catalog.to_regprocedure('private.potencial_rechazo(uuid,uuid)'));
  if v_huellas is distinct from
       'crm.bandera_activa(text)=bb817f2b07b561356959f25dc3aae4dc'
    || ' private.es_lector_global()=5b8ac0c37dcbf5b82057d7b98c65c303'
    || ' private.potencial_rechazo(uuid,uuid)=8893beeecea076e7fd7dbafec174500f'
    || ' private.puede_acceder_crm()=4e2c1caf7ead51be450d5018be4c6092'
    || ' private.rol_crm(uuid)=16960a2a21cc5c372431c2dd67acafe4'
    || ' private.vendedor_ids_visibles(uuid)=45ae492c03234b80336c0b8f5c8ac09b' then
    raise exception 'PREFLIGHT potencial_lectura: un ayudante de visibilidad no es el ensayado: %', coalesce(v_huellas, '(ninguno)');
  end if;

  -- Las policies que deciden qué leads se LEEN: exactamente la permisiva leads_select (la que el
  -- núcleo copia) y el gate restrictivo crm_actor_activo_gate (el que la puerta invoca). Una
  -- policy de lectura nueva o un cambio en estas dos dejaría la puerta viendo de más o de menos.
  select pg_catalog.string_agg(
           pol.polname::text || '|' || pol.polcmd::text || '|' || pol.polpermissive::text || '|'
           || pol.polroles::pg_catalog.regrole[]::text || '|' || pg_catalog.md5(pg_catalog.pg_get_expr(pol.polqual, pol.polrelid)),
           ' ## ' order by pol.polname)
    into v_policies
  from pg_catalog.pg_policy pol
  where pol.polrelid = 'crm.leads'::pg_catalog.regclass and pol.polcmd in ('r', '*');
  if v_policies is distinct from
       'crm_actor_activo_gate|*|false|{authenticated}|c5e6c90632bc616212336e1d089a68b3'
    || ' ## leads_select|r|true|{authenticated}|073deaeb5700bac14209ec795b71567e' then
    raise exception 'PREFLIGHT potencial_lectura: las policies de lectura de crm.leads no son las ensayadas: %', coalesce(v_policies, '(ninguna)');
  end if;
end;
$preflight$;

-- ── 1 · Cuándo es la próxima pasada de la tarea ───────────────────────────────
create function private.potencial_proxima_corrida(p_instante timestamptz)
returns date
language sql
immutable
security invoker
set search_path = ''
as $function$
  -- La tarea crm-potencial-lead-caducidad se programa a las 05:10 y a las 05:40 Lima (10:10 y 10:40
  -- GMT). Horario NOMINAL: a las 05:40 en punto la última pasada puede no haber arrancado todavía
  -- (Codex f3a r2), así que hasta las 05:45 se sigue respondiendo HOY; desde las 05:45, mañana.
  select case
    when (p_instante at time zone 'America/Lima')::time < time '05:45'
      then (p_instante at time zone 'America/Lima')::date
    else (p_instante at time zone 'America/Lima')::date + 1
  end;
$function$;
comment on function private.potencial_proxima_corrida(timestamptz) is
'Fecha (Lima) de la próxima pasada de la tarea de caducidad del potencial según su horario NOMINAL: hoy hasta las 05:45 Lima (la última pasada se programa a las 05:40; cinco minutos de margen), después mañana. No mira si la pasada ya corrió. Debe ir a la par del job crm-potencial-lead-caducidad (10,40 10 * * * GMT): lo comprueba el postflight de la migración de lectura. Sin EXECUTE para la API.';

-- ── 2 · Cuándo bajaría una marca, y a qué nivel ───────────────────────────────
create function private.potencial_proxima_baja(p_nivel crm.nivel_potencial, p_reloj_dia date, p_desde date)
returns table (baja_a crm.nivel_potencial, baja_el date)
language plpgsql
immutable
security invoker
set search_path = ''
as $function$
declare
  v_dia date;
  v_nuevo crm.nivel_potencial;
begin
  if p_nivel is null or p_reloj_dia is null or p_desde is null then
    return;
  end if;
  -- Un nivel que no baja ni con todos los días del mundo (frío) no se recorre. Se le pregunta a
  -- la regla; no se copia aquí qué niveles bajan.
  if (private.potencial_nivel_tras(p_nivel, 2147483647) < p_nivel) is not true then
    return;
  end if;
  -- De la próxima corrida en adelante, la primera fecha en que la regla da un nivel menor. 21 días
  -- cubren de sobra los 10 días hábiles más sus domingos; para en la primera que encuentra.
  for i in 0..21 loop
    v_dia := p_desde + i;
    v_nuevo := private.potencial_nivel_tras(p_nivel, private.dias_lunes_a_sabado(p_reloj_dia, v_dia));
    if v_nuevo < p_nivel then
      baja_a := v_nuevo;
      baja_el := v_dia;
      return next;
      return;
    end if;
  end loop;
  return;
end;
$function$;
comment on function private.potencial_proxima_baja(crm.nivel_potencial, date, date) is
'Primera fecha, desde p_desde (la próxima pasada de la tarea), en que la regla de la caducidad (private.potencial_nivel_tras con private.dias_lunes_a_sabado desde el día del reloj) da un nivel menor, y ese nivel. Sin filas si el nivel nunca baja o falta un dato. Sin EXECUTE para la API.';

-- ── 3 · Núcleo de la lectura ──────────────────────────────────────────────────
create function private.potencial_lectura(p_actor uuid, p_lead_ids uuid[], p_hoy date, p_corte timestamptz, p_proxima date)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $function$
declare
  v_rol text;
  v_lector boolean;
  v_visibles uuid[];
  v_items jsonb;
begin
  if p_actor is null or p_hoy is null or p_corte is null or p_proxima is null then
    raise exception 'Actor, fecha, instante de corte y próxima corrida requeridos' using errcode = '22023';
  end if;
  -- El actor es SIEMPRE el de la sesión (Codex f3a r1): los ayudantes de visibilidad miran
  -- auth.uid(), y con otro actor el rol y el ámbito saldrían de identidades distintas.
  if p_actor is distinct from (select auth.uid()) then
    raise exception 'El actor no es el de la sesión' using errcode = '42501';
  end if;
  if p_lead_ids is null or pg_catalog.cardinality(p_lead_ids) = 0 then
    return '[]'::jsonb;
  end if;

  v_rol := private.rol_crm(p_actor);
  v_lector := private.es_lector_global();
  -- Se resuelve UNA vez (la policy lo evalúa como SubPlan en cada fila).
  v_visibles := array(select private.vendedor_ids_visibles(p_actor));

  select coalesce(pg_catalog.jsonb_agg(f.item order by f.lead_id), '[]'::jsonb)
    into v_items
  from (
    select
      l.id as lead_id,
      pg_catalog.jsonb_build_object(
        'lead_id', l.id,
        'nivel', p.nivel,
        'origen', p.origen,
        'nivel_marcado', m.nivel_marcado,
        'marcado_en', p.marcado_en,
        'dias_sin_gestion', r.dias,
        'baja_a', b.baja_a,
        'baja_el', b.baja_el,
        -- La MISMA regla de la puerta de marcar; cualquier valor que no sea 'ok' (NULL incluido) es no.
        'puede_marcar', coalesce(private.potencial_rechazo(p_actor, l.id) = 'ok', false)
      ) as item
    from crm.leads l
    left join crm.lead_potencial p on p.lead_id = l.id
    -- El último nivel que puso una PERSONA: si la marca bajó sola, es el nivel de antes.
    left join lateral (
      select e.nivel_nuevo as nivel_marcado
      from crm.lead_potencial_eventos e
      where e.lead_id = p.lead_id and e.motivo = 'manual'
      order by e.orden desc
      limit 1
    ) m on true
    -- El reloj y los días, con las funciones de la fase 2 (las mismas que usa la tarea).
    left join lateral (
      select x.reloj_dia, private.dias_lunes_a_sabado(x.reloj_dia, p_hoy) as dias
      from (select (private.potencial_reloj(p.lead_id, p.marcado_en, p_corte) at time zone 'America/Lima')::date as reloj_dia) x
      where p.lead_id is not null
    ) r on true
    -- La primera madrugada, desde la próxima pasada de la tarea, en que la bajaría si nadie
    -- gestiona, y a qué nivel. Solo leads abiertos: la tarea no toca los cerrados.
    left join lateral (
      select x.baja_a, x.baja_el
      from private.potencial_proxima_baja(p.nivel, r.reloj_dia, p_proxima) x
      where l.etapa is not null and l.etapa not in ('convertido', 'descartado')
    ) b on true
    where l.id = any (p_lead_ids)
      -- ── ESPEJO EXACTO de la policy leads_select (fijada por md5 en el preflight) ──
      --   activo = true and ( vendedor_id in (vendedor_ids_visibles(uid))
      --                       or (vendedor_id is null and asignado_supervisor_id in (...))
      --                       or rol_crm(uid) = 'gerencia' or es_lector_global() )
      -- El lector global va DENTRO del activo: ve todo lo vivo y nada de lo borrado.
      and l.activo = true
      and (
        l.vendedor_id = any (v_visibles)
        or (l.vendedor_id is null and l.asignado_supervisor_id = any (v_visibles))
        or v_rol = 'gerencia'
        or v_lector
      )
  ) f;

  return v_items;
end;
$function$;
comment on function private.potencial_lectura(uuid, uuid[], date, timestamptz, date) is
'Lectura de la marca de potencial: un ítem por cada lead pedido que el actor puede ver (espejo de la policy leads_select; el actor debe ser el de la sesión, si no 42501). Por lead: nivel vigente (null sin marca), origen, último nivel puesto por una persona, cuándo, días completos sin gestión (lunes a sábado), a qué nivel bajará y en qué madrugada desde la próxima pasada de la tarea, y si el actor puede marcarlo (private.potencial_rechazo). No mira la bandera ni el gate del CRM: eso lo hace la puerta. Sin EXECUTE para la API.';

-- ── 4 · Puerta ─────────────────────────────────────────────────────────────────
create function crm.potencial_leads_fn(p_lead_ids uuid[])
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
begin
  if v_actor is null then
    raise exception 'Sesión requerida' using errcode = '42501';
  end if;
  -- El gate RESTRICTIVO de crm.leads (crm_actor_activo_gate) se INVOCA en vez de copiarse: quien
  -- no es del CRM ni lector global, o fue dado de baja, no pregunta.
  if private.puede_acceder_crm() is not true then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  -- Sirve a una página en pantalla, no a un volcado (mismo tope que crm.cierres_estado_fn).
  if p_lead_ids is not null and pg_catalog.cardinality(p_lead_ids) > 200 then
    raise exception 'Parámetro p_lead_ids inválido: máximo 200' using errcode = '22023';
  end if;
  -- Con la bandera apagada la pantalla no pinta nada del potencial y aquí no se lee nada.
  if crm.bandera_activa('potencial_lead') is not true then
    return pg_catalog.jsonb_build_object('version', 1, 'habilitada', false, 'items', '[]'::jsonb);
  end if;

  return pg_catalog.jsonb_build_object(
    'version', 1,
    'habilitada', true,
    'items', private.potencial_lectura(
      v_actor, p_lead_ids, (pg_catalog.now() at time zone 'America/Lima')::date, pg_catalog.now(),
      private.potencial_proxima_corrida(pg_catalog.now()))
  );
end;
$function$;
comment on function crm.potencial_leads_fn(uuid[]) is
'Puerta de lectura del potencial del lead. Devuelve {version, habilitada, items}: con la bandera potencial_lead apagada, habilitada=false e items vacío; encendida, un ítem por cada lead pedido que el actor puede ver: {lead_id, nivel, origen, nivel_marcado, marcado_en, dias_sin_gestion, baja_a, baja_el, puede_marcar}. Máximo 200 ids (22023). Sin sesión o fuera del CRM: 42501. Solo lectura.';

-- ── 5 · Dueños y permisos ──────────────────────────────────────────────────────
alter function private.potencial_proxima_corrida(timestamptz) owner to postgres;
alter function private.potencial_proxima_baja(crm.nivel_potencial, date, date) owner to postgres;
alter function private.potencial_lectura(uuid, uuid[], date, timestamptz, date) owner to postgres;
alter function crm.potencial_leads_fn(uuid[]) owner to postgres;
revoke all on function private.potencial_proxima_corrida(timestamptz) from public, anon, authenticated, service_role;
revoke all on function private.potencial_proxima_baja(crm.nivel_potencial, date, date) from public, anon, authenticated, service_role;
revoke all on function private.potencial_lectura(uuid, uuid[], date, timestamptz, date) from public, anon, authenticated, service_role;
revoke all on function crm.potencial_leads_fn(uuid[]) from public, anon, authenticated, service_role;
grant execute on function crm.potencial_leads_fn(uuid[]) to authenticated;

-- ── 6 · Postflight ─────────────────────────────────────────────────────────────
do $postflight$
declare
  v_puerta pg_catalog.regprocedure := 'crm.potencial_leads_fn(uuid[])'::pg_catalog.regprocedure;
  v_nucleo pg_catalog.regprocedure := 'private.potencial_lectura(uuid,uuid[],date,timestamp with time zone,date)'::pg_catalog.regprocedure;
  v_privadas pg_catalog.regprocedure[] := array[
    'private.potencial_lectura(uuid,uuid[],date,timestamp with time zone,date)'::pg_catalog.regprocedure,
    'private.potencial_proxima_baja(crm.nivel_potencial,date,date)'::pg_catalog.regprocedure,
    'private.potencial_proxima_corrida(timestamp with time zone)'::pg_catalog.regprocedure
  ];
begin
  perform pg_catalog.set_config('search_path', '', true);

  -- Puerta: DEFINER, STABLE, dueño postgres y configuración EXACTA (solo search_path vacío: un SET de
  -- más podría cambiar la identidad que ve auth.uid(); Codex f3a r1). ACL explícita: postgres y
  -- authenticated, y authenticated solo EXECUTE y sin opción de concederlo. Permisos EFECTIVOS:
  -- authenticated la ejecuta; anon y service_role no.
  if (
    exists (
      select 1 from pg_catalog.pg_proc p
      where p.oid = v_puerta and p.prosecdef and p.proowner = 'postgres'::pg_catalog.regrole
        and p.provolatile = 's'
        and p.proconfig = array['search_path=""']::text[]
        and p.proacl is not null
    )
    and not exists (select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
                    where p.oid = v_puerta
                      and (a.grantee not in ('postgres'::pg_catalog.regrole, 'authenticated'::pg_catalog.regrole)
                           or (a.grantee = 'authenticated'::pg_catalog.regrole
                               and (a.is_grantable or a.privilege_type <> 'EXECUTE'))))
    and pg_catalog.has_function_privilege('authenticated', v_puerta, 'EXECUTE')
    and not pg_catalog.has_function_privilege('anon', v_puerta, 'EXECUTE')
    and not pg_catalog.has_function_privilege('service_role', v_puerta, 'EXECUTE')
  ) is not true then
    raise exception 'POSTFLIGHT potencial_lectura: la puerta no quedó DEFINER/STABLE/postgres/solo search_path vacío/EXECUTE solo authenticated y sin opción de concederlo';
  end if;

  -- Privadas: INVOKER, dueño postgres, configuración EXACTA, ACL explícita solo de postgres y
  -- permisos EFECTIVOS en cero para los tres roles de la API.
  if (
    (select count(*) from pg_catalog.pg_proc p
      where p.oid = any (v_privadas) and not p.prosecdef and p.proowner = 'postgres'::pg_catalog.regrole
        and p.proconfig = array['search_path=""']::text[]
        and p.proacl is not null) = 3
    and not exists (select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
                    where p.oid = any (v_privadas) and a.grantee <> 'postgres'::pg_catalog.regrole)
    and not exists (
      select 1
      from pg_catalog.unnest(v_privadas) f(fn), pg_catalog.unnest(array['anon', 'authenticated', 'service_role']) r(rol)
      where pg_catalog.has_function_privilege(r.rol, f.fn, 'EXECUTE'))
    and (select p.provolatile from pg_catalog.pg_proc p where p.oid = v_nucleo) = 's'
  ) is not true then
    raise exception 'POSTFLIGHT potencial_lectura: los ayudantes privados no quedaron INVOKER/solo search_path vacío/sin EXECUTE para la API';
  end if;

  -- Ninguna cuenta filas (censo de contadores crudos de leads y citas).
  if exists (select 1 from pg_catalog.pg_proc p
             where (p.oid = v_puerta or p.oid = any (v_privadas)) and p.prosrc ~* '(count|sum)\s*\(') then
    raise exception 'POSTFLIGHT potencial_lectura: una de las funciones usa un agregado de conteo';
  end if;

  -- Contrato de la próxima corrida y de la próxima bajada, a mano (no depende de la fecha de hoy).
  if (
    private.potencial_proxima_corrida('2026-10-05 05:40:00-05'::timestamptz) = '2026-10-05'::date
    and private.potencial_proxima_corrida('2026-10-05 05:44:59-05'::timestamptz) = '2026-10-05'::date
    and private.potencial_proxima_corrida('2026-10-05 05:45:00-05'::timestamptz) = '2026-10-06'::date
    and private.potencial_proxima_corrida('2026-10-05 23:59:59-05'::timestamptz) = '2026-10-06'::date
    and private.potencial_proxima_corrida('2026-10-06 00:00:00-05'::timestamptz) = '2026-10-06'::date
    and (select b.baja_a::text || '@' || b.baja_el::text
         from private.potencial_proxima_baja('estrella', '2026-10-05', '2026-10-06') b) = 'tibio@2026-10-11'
    and (select b.baja_a::text || '@' || b.baja_el::text
         from private.potencial_proxima_baja('estrella', '2026-10-05', '2026-10-17') b) = 'frio@2026-10-17'
    and (select b.baja_a::text || '@' || b.baja_el::text
         from private.potencial_proxima_baja('tibio', '2026-10-05', '2026-10-06') b) = 'frio@2026-10-17'
    and not exists (select 1 from private.potencial_proxima_baja('frio', '2026-10-05', '2026-10-06'))
  ) is not true then
    raise exception 'POSTFLIGHT potencial_lectura: la próxima corrida o la próxima bajada no son las acordadas';
  end if;

  -- La próxima corrida supone la tarea de la fase 2 TAL CUAL: un solo job con ese nombre, activo, con
  -- su horario, su comando, su usuario y esta base, y pg_cron contando en GMT (Codex f3a r2: nombre y
  -- horario solos no acreditan la tarea). Sin pg_cron (un banco) no se puede comprobar: se avisa abajo.
  if pg_catalog.to_regclass('cron.job') is not null then
    if (
      (select count(*) from cron.job j where j.jobname = 'crm-potencial-lead-caducidad') = 1
      and (select count(*) from cron.job j
            where j.jobname = 'crm-potencial-lead-caducidad' and j.schedule = '10,40 10 * * *'
              and j.command = 'select private.potencial_caducar()' and j.active
              and j.username = 'postgres' and j.database = pg_catalog.current_database()) = 1
      and coalesce(pg_catalog.current_setting('cron.timezone', true), 'GMT') in ('GMT', 'UTC', 'Etc/UTC')
    ) is not true then
      raise exception 'POSTFLIGHT potencial_lectura: la tarea crm-potencial-lead-caducidad no es la esperada (10,40 10 * * * GMT, select private.potencial_caducar(), postgres, activa): con otra, la próxima corrida se calcularía mal';
    end if;
  end if;

  -- El núcleo no acepta un actor que no sea el de la sesión (aquí no hay sesión de usuario).
  begin
    perform private.potencial_lectura('00000000-0000-0000-0000-000000000001'::uuid, null,
                                      '2026-10-06'::date, pg_catalog.now(), '2026-10-06'::date);
    raise exception 'POSTFLIGHT potencial_lectura: el núcleo aceptó un actor que no es el de la sesión' using errcode = 'P0001';
  exception when insufficient_privilege then
    null;
  end;

  raise notice 'potencial_lectura OK: 3 ayudantes INVOKER sin EXECUTE de la API, puerta DEFINER STABLE solo authenticated, sin conteos, tarea de caducidad %.',
    case when pg_catalog.to_regclass('cron.job') is null then 'NO COMPROBADA (sin pg_cron en esta base)' else 'comprobada' end;
end;
$postflight$;

commit;
$mig$])) then
    raise exception 'REGISTRO: la versión 20261001151704 ya está registrada con otro nombre o contenido';
  end if;
end $chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20261001151704', 'crm_potencial_lead_lectura', array[$mig$-- 20261001151704_crm_potencial_lead_lectura.sql
--
-- Potencial del lead · FASE 3, entrega A (servidor): la puerta de LECTURA. Plan aprobado por
-- Miguel el 01/10/2026 («vamos dale» al plan en dos entregas: A marcar y ver, B filtrar). Nota
-- del vault: «Potencial del lead - Frio Tibio Estrella (2026-09-30)», «Fase 3 · mapa y plan».
--
-- QUÉ HACE
--   · private.potencial_proxima_corrida(instante): la fecha (Lima) de la próxima pasada de la tarea
--     de la fase 2, por su HORARIO NOMINAL (no mira si la pasada ya corrió). La tarea se programa a
--     las 05:10 y 05:40 Lima: hasta las 05:45 se responde «hoy» (cinco minutos de margen para que la
--     última pasada arranque y termine; dura menos de un segundo); desde las 05:45, «mañana». El
--     postflight comprueba que el job sigue teniendo ese horario, ese comando y ese destino.
--   · private.potencial_proxima_baja(nivel, día del reloj, desde): la primera fecha, desde la
--     próxima corrida, en que la regla de la fase 2 da un nivel menor, y ese nivel. Bucle que para
--     en la primera (no recorre fechas de más) y no hace nada con un nivel que nunca baja.
--   · private.potencial_lectura(actor, lead_ids, hoy, corte, próxima corrida): por cada lead
--     pedido que el actor PUEDE VER (espejo de la policy leads_select), la marca vigente y lo que
--     la pantalla tiene que decir: nivel, origen (manual | caducidad), el último nivel que puso una
--     PERSONA, cuándo se marcó, los días completos sin gestión (lunes a sábado), a qué nivel
--     bajará y en qué madrugada si nadie gestiona, y si el actor puede marcarlo. Un lead visible
--     sin marca viaja con nivel null. UNA sola regla: los días salen de private.potencial_reloj y
--     private.dias_lunes_a_sabado, el nivel siguiente de private.potencial_nivel_tras (fase 2), y
--     el permiso de private.potencial_rechazo (la misma función que decide en la puerta de
--     marcar, fase 1). Recibe hoy, el corte y la próxima corrida para ensayarse con calendario.
--     El actor DEBE ser el de la sesión (Codex f3a r1): con otro, 42501.
--   · crm.potencial_leads_fn(uuid[]): la puerta. Sesión, el gate restrictivo del CRM
--     (private.puede_acceder_crm, invocado y no copiado), tope de 200 ids y la bandera
--     'potencial_lead': apagada devuelve {version:1, habilitada:false, items:[]} SIN leer nada;
--     encendida, {version:1, habilitada:true, items:[…]}.
-- QUÉ SIGNIFICA baja_el (Codex f3a r1 y r2): la primera madrugada, contando desde el siguiente
--   horario NOMINAL de la tarea, en que la regla la bajaría con lo que se sabe AHORA. No es una
--   promesa ni acredita ejecución: un contacto o una marca nuevos la aplazan; si el lead está ocupado
--   o la pasada llega a su límite de 200, la bajada queda para la pasada siguiente; y si pg_cron se
--   retrasa más allá de las 05:45, una pasada de hoy todavía puede bajarla hoy. La pantalla lo dice
--   siempre en condicional («si no se gestiona»).
-- NO TOCA nada de lo existente: ninguna puerta de cartera, cola, SLA ni Gestión Diaria cambia. La
--   pantalla une la marca por lead_id, igual que hace con crm.cierres_estado_fn.
-- CAPAS: puerta crm (valida, autoriza, delega) → núcleo private (INVOKER, sin EXECUTE para la
--   API) → tablas (crm.lead_potencial y su historial, sin grants para la API).
-- SECURITY DEFINER, justificación: las tablas de la marca no tienen grants para la API (fase 1,
--   auditor-rls r1) y el reloj y la regla de la fase 2 no tienen EXECUTE para la API: una puerta
--   INVOKER no puede leerlos. Molde: crm.cierres_estado_fn. La visibilidad se verifica de forma
--   explícita con el ESPEJO de leads_select; el preflight fija por md5 esa policy, el gate
--   restrictivo de crm.leads y los ayudantes en que se apoyan: si alguno cambió desde el ensayo en
--   el banco, la migración se niega y hay que volver a revisarla.
-- SIN contar: private.contadores_crudos_leads_citas vigila toda función que nombre crm.leads y
--   use un agregado de conteo; aquí no hay ninguno (jsonb_agg y cardinality).
-- REVERSA: supabase/scripts/potencial-lead/reversa-lectura.sql (quita las dos funciones; no hay
--   datos que perder).

begin;
set local lock_timeout = '5s';

-- ── 0 · Preflight ──────────────────────────────────────────────────────────────
do $preflight$
declare
  v_huellas text;
  v_policies text;
begin
  -- Texto de catálogo independiente de la sesión: todo calificado y sin comillas forzadas
  -- (quote_all_identifiers cambiaría el texto de pg_get_expr y con él las huellas; Codex f3a r1).
  perform pg_catalog.set_config('search_path', '', true);
  perform pg_catalog.set_config('quote_all_identifiers', 'off', true);

  if (
    pg_catalog.to_regclass('crm.lead_potencial') is not null
    and pg_catalog.to_regclass('crm.lead_potencial_eventos') is not null
    and pg_catalog.to_regprocedure('private.potencial_rechazo(uuid,uuid)') is not null
    and pg_catalog.to_regprocedure('private.potencial_reloj(uuid,timestamp with time zone,timestamp with time zone)') is not null
    and pg_catalog.to_regprocedure('private.dias_lunes_a_sabado(date,date)') is not null
    and pg_catalog.to_regprocedure('private.potencial_nivel_tras(crm.nivel_potencial,integer)') is not null
    and exists (select 1 from crm.multiempresa_flags f where f.nombre = 'potencial_lead')
  ) is not true then
    raise exception 'PREFLIGHT potencial_lectura: faltan la fase 1 (20260930213647) o la fase 2 (20260930235917)';
  end if;

  if (
    not exists (
      select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
      where (n.nspname = 'crm' and p.proname = 'potencial_leads_fn')
         or (n.nspname = 'private' and p.proname in ('potencial_lectura', 'potencial_proxima_baja', 'potencial_proxima_corrida')))
  ) is not true then
    raise exception 'PREFLIGHT potencial_lectura: ya aplicada o aplicada a medias';
  end if;

  -- La visibilidad de la puerta descansa en estos ayudantes: identidad por cuerpo + DEFINER +
  -- volatilidad + configuración + dueño (pg_get_functiondef no sirve: cambia con la sesión).
  select pg_catalog.string_agg(
           p.oid::pg_catalog.regprocedure::text || '=' ||
           pg_catalog.md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|'
                          || coalesce(pg_catalog.array_to_string(p.proconfig, ','), '') || '|' || p.proowner::pg_catalog.regrole::text),
           ' ' order by p.oid::pg_catalog.regprocedure::text)
    into v_huellas
  from pg_catalog.pg_proc p
  where p.oid in (pg_catalog.to_regprocedure('private.rol_crm(uuid)'),
                  pg_catalog.to_regprocedure('private.vendedor_ids_visibles(uuid)'),
                  pg_catalog.to_regprocedure('private.es_lector_global()'),
                  pg_catalog.to_regprocedure('private.puede_acceder_crm()'),
                  pg_catalog.to_regprocedure('crm.bandera_activa(text)'),
                  pg_catalog.to_regprocedure('private.potencial_rechazo(uuid,uuid)'));
  if v_huellas is distinct from
       'crm.bandera_activa(text)=bb817f2b07b561356959f25dc3aae4dc'
    || ' private.es_lector_global()=5b8ac0c37dcbf5b82057d7b98c65c303'
    || ' private.potencial_rechazo(uuid,uuid)=8893beeecea076e7fd7dbafec174500f'
    || ' private.puede_acceder_crm()=4e2c1caf7ead51be450d5018be4c6092'
    || ' private.rol_crm(uuid)=16960a2a21cc5c372431c2dd67acafe4'
    || ' private.vendedor_ids_visibles(uuid)=45ae492c03234b80336c0b8f5c8ac09b' then
    raise exception 'PREFLIGHT potencial_lectura: un ayudante de visibilidad no es el ensayado: %', coalesce(v_huellas, '(ninguno)');
  end if;

  -- Las policies que deciden qué leads se LEEN: exactamente la permisiva leads_select (la que el
  -- núcleo copia) y el gate restrictivo crm_actor_activo_gate (el que la puerta invoca). Una
  -- policy de lectura nueva o un cambio en estas dos dejaría la puerta viendo de más o de menos.
  select pg_catalog.string_agg(
           pol.polname::text || '|' || pol.polcmd::text || '|' || pol.polpermissive::text || '|'
           || pol.polroles::pg_catalog.regrole[]::text || '|' || pg_catalog.md5(pg_catalog.pg_get_expr(pol.polqual, pol.polrelid)),
           ' ## ' order by pol.polname)
    into v_policies
  from pg_catalog.pg_policy pol
  where pol.polrelid = 'crm.leads'::pg_catalog.regclass and pol.polcmd in ('r', '*');
  if v_policies is distinct from
       'crm_actor_activo_gate|*|false|{authenticated}|c5e6c90632bc616212336e1d089a68b3'
    || ' ## leads_select|r|true|{authenticated}|073deaeb5700bac14209ec795b71567e' then
    raise exception 'PREFLIGHT potencial_lectura: las policies de lectura de crm.leads no son las ensayadas: %', coalesce(v_policies, '(ninguna)');
  end if;
end;
$preflight$;

-- ── 1 · Cuándo es la próxima pasada de la tarea ───────────────────────────────
create function private.potencial_proxima_corrida(p_instante timestamptz)
returns date
language sql
immutable
security invoker
set search_path = ''
as $function$
  -- La tarea crm-potencial-lead-caducidad se programa a las 05:10 y a las 05:40 Lima (10:10 y 10:40
  -- GMT). Horario NOMINAL: a las 05:40 en punto la última pasada puede no haber arrancado todavía
  -- (Codex f3a r2), así que hasta las 05:45 se sigue respondiendo HOY; desde las 05:45, mañana.
  select case
    when (p_instante at time zone 'America/Lima')::time < time '05:45'
      then (p_instante at time zone 'America/Lima')::date
    else (p_instante at time zone 'America/Lima')::date + 1
  end;
$function$;
comment on function private.potencial_proxima_corrida(timestamptz) is
'Fecha (Lima) de la próxima pasada de la tarea de caducidad del potencial según su horario NOMINAL: hoy hasta las 05:45 Lima (la última pasada se programa a las 05:40; cinco minutos de margen), después mañana. No mira si la pasada ya corrió. Debe ir a la par del job crm-potencial-lead-caducidad (10,40 10 * * * GMT): lo comprueba el postflight de la migración de lectura. Sin EXECUTE para la API.';

-- ── 2 · Cuándo bajaría una marca, y a qué nivel ───────────────────────────────
create function private.potencial_proxima_baja(p_nivel crm.nivel_potencial, p_reloj_dia date, p_desde date)
returns table (baja_a crm.nivel_potencial, baja_el date)
language plpgsql
immutable
security invoker
set search_path = ''
as $function$
declare
  v_dia date;
  v_nuevo crm.nivel_potencial;
begin
  if p_nivel is null or p_reloj_dia is null or p_desde is null then
    return;
  end if;
  -- Un nivel que no baja ni con todos los días del mundo (frío) no se recorre. Se le pregunta a
  -- la regla; no se copia aquí qué niveles bajan.
  if (private.potencial_nivel_tras(p_nivel, 2147483647) < p_nivel) is not true then
    return;
  end if;
  -- De la próxima corrida en adelante, la primera fecha en que la regla da un nivel menor. 21 días
  -- cubren de sobra los 10 días hábiles más sus domingos; para en la primera que encuentra.
  for i in 0..21 loop
    v_dia := p_desde + i;
    v_nuevo := private.potencial_nivel_tras(p_nivel, private.dias_lunes_a_sabado(p_reloj_dia, v_dia));
    if v_nuevo < p_nivel then
      baja_a := v_nuevo;
      baja_el := v_dia;
      return next;
      return;
    end if;
  end loop;
  return;
end;
$function$;
comment on function private.potencial_proxima_baja(crm.nivel_potencial, date, date) is
'Primera fecha, desde p_desde (la próxima pasada de la tarea), en que la regla de la caducidad (private.potencial_nivel_tras con private.dias_lunes_a_sabado desde el día del reloj) da un nivel menor, y ese nivel. Sin filas si el nivel nunca baja o falta un dato. Sin EXECUTE para la API.';

-- ── 3 · Núcleo de la lectura ──────────────────────────────────────────────────
create function private.potencial_lectura(p_actor uuid, p_lead_ids uuid[], p_hoy date, p_corte timestamptz, p_proxima date)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $function$
declare
  v_rol text;
  v_lector boolean;
  v_visibles uuid[];
  v_items jsonb;
begin
  if p_actor is null or p_hoy is null or p_corte is null or p_proxima is null then
    raise exception 'Actor, fecha, instante de corte y próxima corrida requeridos' using errcode = '22023';
  end if;
  -- El actor es SIEMPRE el de la sesión (Codex f3a r1): los ayudantes de visibilidad miran
  -- auth.uid(), y con otro actor el rol y el ámbito saldrían de identidades distintas.
  if p_actor is distinct from (select auth.uid()) then
    raise exception 'El actor no es el de la sesión' using errcode = '42501';
  end if;
  if p_lead_ids is null or pg_catalog.cardinality(p_lead_ids) = 0 then
    return '[]'::jsonb;
  end if;

  v_rol := private.rol_crm(p_actor);
  v_lector := private.es_lector_global();
  -- Se resuelve UNA vez (la policy lo evalúa como SubPlan en cada fila).
  v_visibles := array(select private.vendedor_ids_visibles(p_actor));

  select coalesce(pg_catalog.jsonb_agg(f.item order by f.lead_id), '[]'::jsonb)
    into v_items
  from (
    select
      l.id as lead_id,
      pg_catalog.jsonb_build_object(
        'lead_id', l.id,
        'nivel', p.nivel,
        'origen', p.origen,
        'nivel_marcado', m.nivel_marcado,
        'marcado_en', p.marcado_en,
        'dias_sin_gestion', r.dias,
        'baja_a', b.baja_a,
        'baja_el', b.baja_el,
        -- La MISMA regla de la puerta de marcar; cualquier valor que no sea 'ok' (NULL incluido) es no.
        'puede_marcar', coalesce(private.potencial_rechazo(p_actor, l.id) = 'ok', false)
      ) as item
    from crm.leads l
    left join crm.lead_potencial p on p.lead_id = l.id
    -- El último nivel que puso una PERSONA: si la marca bajó sola, es el nivel de antes.
    left join lateral (
      select e.nivel_nuevo as nivel_marcado
      from crm.lead_potencial_eventos e
      where e.lead_id = p.lead_id and e.motivo = 'manual'
      order by e.orden desc
      limit 1
    ) m on true
    -- El reloj y los días, con las funciones de la fase 2 (las mismas que usa la tarea).
    left join lateral (
      select x.reloj_dia, private.dias_lunes_a_sabado(x.reloj_dia, p_hoy) as dias
      from (select (private.potencial_reloj(p.lead_id, p.marcado_en, p_corte) at time zone 'America/Lima')::date as reloj_dia) x
      where p.lead_id is not null
    ) r on true
    -- La primera madrugada, desde la próxima pasada de la tarea, en que la bajaría si nadie
    -- gestiona, y a qué nivel. Solo leads abiertos: la tarea no toca los cerrados.
    left join lateral (
      select x.baja_a, x.baja_el
      from private.potencial_proxima_baja(p.nivel, r.reloj_dia, p_proxima) x
      where l.etapa is not null and l.etapa not in ('convertido', 'descartado')
    ) b on true
    where l.id = any (p_lead_ids)
      -- ── ESPEJO EXACTO de la policy leads_select (fijada por md5 en el preflight) ──
      --   activo = true and ( vendedor_id in (vendedor_ids_visibles(uid))
      --                       or (vendedor_id is null and asignado_supervisor_id in (...))
      --                       or rol_crm(uid) = 'gerencia' or es_lector_global() )
      -- El lector global va DENTRO del activo: ve todo lo vivo y nada de lo borrado.
      and l.activo = true
      and (
        l.vendedor_id = any (v_visibles)
        or (l.vendedor_id is null and l.asignado_supervisor_id = any (v_visibles))
        or v_rol = 'gerencia'
        or v_lector
      )
  ) f;

  return v_items;
end;
$function$;
comment on function private.potencial_lectura(uuid, uuid[], date, timestamptz, date) is
'Lectura de la marca de potencial: un ítem por cada lead pedido que el actor puede ver (espejo de la policy leads_select; el actor debe ser el de la sesión, si no 42501). Por lead: nivel vigente (null sin marca), origen, último nivel puesto por una persona, cuándo, días completos sin gestión (lunes a sábado), a qué nivel bajará y en qué madrugada desde la próxima pasada de la tarea, y si el actor puede marcarlo (private.potencial_rechazo). No mira la bandera ni el gate del CRM: eso lo hace la puerta. Sin EXECUTE para la API.';

-- ── 4 · Puerta ─────────────────────────────────────────────────────────────────
create function crm.potencial_leads_fn(p_lead_ids uuid[])
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
begin
  if v_actor is null then
    raise exception 'Sesión requerida' using errcode = '42501';
  end if;
  -- El gate RESTRICTIVO de crm.leads (crm_actor_activo_gate) se INVOCA en vez de copiarse: quien
  -- no es del CRM ni lector global, o fue dado de baja, no pregunta.
  if private.puede_acceder_crm() is not true then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  -- Sirve a una página en pantalla, no a un volcado (mismo tope que crm.cierres_estado_fn).
  if p_lead_ids is not null and pg_catalog.cardinality(p_lead_ids) > 200 then
    raise exception 'Parámetro p_lead_ids inválido: máximo 200' using errcode = '22023';
  end if;
  -- Con la bandera apagada la pantalla no pinta nada del potencial y aquí no se lee nada.
  if crm.bandera_activa('potencial_lead') is not true then
    return pg_catalog.jsonb_build_object('version', 1, 'habilitada', false, 'items', '[]'::jsonb);
  end if;

  return pg_catalog.jsonb_build_object(
    'version', 1,
    'habilitada', true,
    'items', private.potencial_lectura(
      v_actor, p_lead_ids, (pg_catalog.now() at time zone 'America/Lima')::date, pg_catalog.now(),
      private.potencial_proxima_corrida(pg_catalog.now()))
  );
end;
$function$;
comment on function crm.potencial_leads_fn(uuid[]) is
'Puerta de lectura del potencial del lead. Devuelve {version, habilitada, items}: con la bandera potencial_lead apagada, habilitada=false e items vacío; encendida, un ítem por cada lead pedido que el actor puede ver: {lead_id, nivel, origen, nivel_marcado, marcado_en, dias_sin_gestion, baja_a, baja_el, puede_marcar}. Máximo 200 ids (22023). Sin sesión o fuera del CRM: 42501. Solo lectura.';

-- ── 5 · Dueños y permisos ──────────────────────────────────────────────────────
alter function private.potencial_proxima_corrida(timestamptz) owner to postgres;
alter function private.potencial_proxima_baja(crm.nivel_potencial, date, date) owner to postgres;
alter function private.potencial_lectura(uuid, uuid[], date, timestamptz, date) owner to postgres;
alter function crm.potencial_leads_fn(uuid[]) owner to postgres;
revoke all on function private.potencial_proxima_corrida(timestamptz) from public, anon, authenticated, service_role;
revoke all on function private.potencial_proxima_baja(crm.nivel_potencial, date, date) from public, anon, authenticated, service_role;
revoke all on function private.potencial_lectura(uuid, uuid[], date, timestamptz, date) from public, anon, authenticated, service_role;
revoke all on function crm.potencial_leads_fn(uuid[]) from public, anon, authenticated, service_role;
grant execute on function crm.potencial_leads_fn(uuid[]) to authenticated;

-- ── 6 · Postflight ─────────────────────────────────────────────────────────────
do $postflight$
declare
  v_puerta pg_catalog.regprocedure := 'crm.potencial_leads_fn(uuid[])'::pg_catalog.regprocedure;
  v_nucleo pg_catalog.regprocedure := 'private.potencial_lectura(uuid,uuid[],date,timestamp with time zone,date)'::pg_catalog.regprocedure;
  v_privadas pg_catalog.regprocedure[] := array[
    'private.potencial_lectura(uuid,uuid[],date,timestamp with time zone,date)'::pg_catalog.regprocedure,
    'private.potencial_proxima_baja(crm.nivel_potencial,date,date)'::pg_catalog.regprocedure,
    'private.potencial_proxima_corrida(timestamp with time zone)'::pg_catalog.regprocedure
  ];
begin
  perform pg_catalog.set_config('search_path', '', true);

  -- Puerta: DEFINER, STABLE, dueño postgres y configuración EXACTA (solo search_path vacío: un SET de
  -- más podría cambiar la identidad que ve auth.uid(); Codex f3a r1). ACL explícita: postgres y
  -- authenticated, y authenticated solo EXECUTE y sin opción de concederlo. Permisos EFECTIVOS:
  -- authenticated la ejecuta; anon y service_role no.
  if (
    exists (
      select 1 from pg_catalog.pg_proc p
      where p.oid = v_puerta and p.prosecdef and p.proowner = 'postgres'::pg_catalog.regrole
        and p.provolatile = 's'
        and p.proconfig = array['search_path=""']::text[]
        and p.proacl is not null
    )
    and not exists (select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
                    where p.oid = v_puerta
                      and (a.grantee not in ('postgres'::pg_catalog.regrole, 'authenticated'::pg_catalog.regrole)
                           or (a.grantee = 'authenticated'::pg_catalog.regrole
                               and (a.is_grantable or a.privilege_type <> 'EXECUTE'))))
    and pg_catalog.has_function_privilege('authenticated', v_puerta, 'EXECUTE')
    and not pg_catalog.has_function_privilege('anon', v_puerta, 'EXECUTE')
    and not pg_catalog.has_function_privilege('service_role', v_puerta, 'EXECUTE')
  ) is not true then
    raise exception 'POSTFLIGHT potencial_lectura: la puerta no quedó DEFINER/STABLE/postgres/solo search_path vacío/EXECUTE solo authenticated y sin opción de concederlo';
  end if;

  -- Privadas: INVOKER, dueño postgres, configuración EXACTA, ACL explícita solo de postgres y
  -- permisos EFECTIVOS en cero para los tres roles de la API.
  if (
    (select count(*) from pg_catalog.pg_proc p
      where p.oid = any (v_privadas) and not p.prosecdef and p.proowner = 'postgres'::pg_catalog.regrole
        and p.proconfig = array['search_path=""']::text[]
        and p.proacl is not null) = 3
    and not exists (select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
                    where p.oid = any (v_privadas) and a.grantee <> 'postgres'::pg_catalog.regrole)
    and not exists (
      select 1
      from pg_catalog.unnest(v_privadas) f(fn), pg_catalog.unnest(array['anon', 'authenticated', 'service_role']) r(rol)
      where pg_catalog.has_function_privilege(r.rol, f.fn, 'EXECUTE'))
    and (select p.provolatile from pg_catalog.pg_proc p where p.oid = v_nucleo) = 's'
  ) is not true then
    raise exception 'POSTFLIGHT potencial_lectura: los ayudantes privados no quedaron INVOKER/solo search_path vacío/sin EXECUTE para la API';
  end if;

  -- Ninguna cuenta filas (censo de contadores crudos de leads y citas).
  if exists (select 1 from pg_catalog.pg_proc p
             where (p.oid = v_puerta or p.oid = any (v_privadas)) and p.prosrc ~* '(count|sum)\s*\(') then
    raise exception 'POSTFLIGHT potencial_lectura: una de las funciones usa un agregado de conteo';
  end if;

  -- Contrato de la próxima corrida y de la próxima bajada, a mano (no depende de la fecha de hoy).
  if (
    private.potencial_proxima_corrida('2026-10-05 05:40:00-05'::timestamptz) = '2026-10-05'::date
    and private.potencial_proxima_corrida('2026-10-05 05:44:59-05'::timestamptz) = '2026-10-05'::date
    and private.potencial_proxima_corrida('2026-10-05 05:45:00-05'::timestamptz) = '2026-10-06'::date
    and private.potencial_proxima_corrida('2026-10-05 23:59:59-05'::timestamptz) = '2026-10-06'::date
    and private.potencial_proxima_corrida('2026-10-06 00:00:00-05'::timestamptz) = '2026-10-06'::date
    and (select b.baja_a::text || '@' || b.baja_el::text
         from private.potencial_proxima_baja('estrella', '2026-10-05', '2026-10-06') b) = 'tibio@2026-10-11'
    and (select b.baja_a::text || '@' || b.baja_el::text
         from private.potencial_proxima_baja('estrella', '2026-10-05', '2026-10-17') b) = 'frio@2026-10-17'
    and (select b.baja_a::text || '@' || b.baja_el::text
         from private.potencial_proxima_baja('tibio', '2026-10-05', '2026-10-06') b) = 'frio@2026-10-17'
    and not exists (select 1 from private.potencial_proxima_baja('frio', '2026-10-05', '2026-10-06'))
  ) is not true then
    raise exception 'POSTFLIGHT potencial_lectura: la próxima corrida o la próxima bajada no son las acordadas';
  end if;

  -- La próxima corrida supone la tarea de la fase 2 TAL CUAL: un solo job con ese nombre, activo, con
  -- su horario, su comando, su usuario y esta base, y pg_cron contando en GMT (Codex f3a r2: nombre y
  -- horario solos no acreditan la tarea). Sin pg_cron (un banco) no se puede comprobar: se avisa abajo.
  if pg_catalog.to_regclass('cron.job') is not null then
    if (
      (select count(*) from cron.job j where j.jobname = 'crm-potencial-lead-caducidad') = 1
      and (select count(*) from cron.job j
            where j.jobname = 'crm-potencial-lead-caducidad' and j.schedule = '10,40 10 * * *'
              and j.command = 'select private.potencial_caducar()' and j.active
              and j.username = 'postgres' and j.database = pg_catalog.current_database()) = 1
      and coalesce(pg_catalog.current_setting('cron.timezone', true), 'GMT') in ('GMT', 'UTC', 'Etc/UTC')
    ) is not true then
      raise exception 'POSTFLIGHT potencial_lectura: la tarea crm-potencial-lead-caducidad no es la esperada (10,40 10 * * * GMT, select private.potencial_caducar(), postgres, activa): con otra, la próxima corrida se calcularía mal';
    end if;
  end if;

  -- El núcleo no acepta un actor que no sea el de la sesión (aquí no hay sesión de usuario).
  begin
    perform private.potencial_lectura('00000000-0000-0000-0000-000000000001'::uuid, null,
                                      '2026-10-06'::date, pg_catalog.now(), '2026-10-06'::date);
    raise exception 'POSTFLIGHT potencial_lectura: el núcleo aceptó un actor que no es el de la sesión' using errcode = 'P0001';
  exception when insufficient_privilege then
    null;
  end;

  raise notice 'potencial_lectura OK: 3 ayudantes INVOKER sin EXECUTE de la API, puerta DEFINER STABLE solo authenticated, sin conteos, tarea de caducidad %.',
    case when pg_catalog.to_regclass('cron.job') is null then 'NO COMPROBADA (sin pg_cron en esta base)' else 'comprobada' end;
end;
$postflight$;

commit;
$mig$])
on conflict (version) do nothing;
do $post$
begin
  if not exists (select 1 from supabase_migrations.schema_migrations
                 where version = '20261001151704' and name = 'crm_potencial_lead_lectura' and cardinality(statements) = 1
                   and md5(statements[1]) = '7c2b85345ddd32e16430c88639628fc2') then
    raise exception 'REGISTRO: la fila 20261001151704 / crm_potencial_lead_lectura no quedó como se esperaba';
  end if;
  raise notice 'REGISTRO: 20261001151704 / crm_potencial_lead_lectura (1 sentencia: el archivo entero)';
end $post$;
commit;
