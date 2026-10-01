-- 20260930235917_crm_potencial_lead_caducidad.sql
--
-- Potencial del lead · FASE 2: la marca baja sola. Plan aprobado por Miguel el 30/09/2026
-- («HAZLO» al plan por fases; «hazlo» tras publicar la fase 1). Reglas de Miguel (30/09):
--   · Estrella → Tibio tras 5 días sin gestión; Tibio → Frío tras 10 días sin gestión.
--   · Cuentan de lunes a sábado; los domingos no. Feriados: día normal (supuesto comunicado).
--   · Cada gestión registrada reinicia el reloj; marcar también (fase 1: marcado_en).
-- Nota del vault: «Potencial del lead - Frio Tibio Estrella (2026-09-30)».
--
-- QUÉ HACE
--   · private.dias_lunes_a_sabado(desde, hasta): días COMPLETOS de lunes a sábado estrictamente
--     entre dos fechas (sin contar ninguna de las dos puntas). La tarea corre de madrugada: el día
--     de hoy aún no pasó y el día de la última gestión tampoco cuenta como «sin gestión».
--   · private.potencial_reloj(lead, marcado_en, corte): lo más reciente entre la última marca
--     humana y el último CONTACTO del lead ANTERIOR al instante de corte (los 5 tipos del índice
--     actividades_contacto_episodio_idx: llamada realizada o no contestada, WhatsApp enviado o
--     recibido, reunión realizada). Las notas no cuentan: el sistema también escribe notas (p. ej.
--     al anular un cierre). Un contacto con fecha futura no congela el reloj (Codex f2 r1 F4): no
--     cuenta hasta que llega su hora. El corte es el INSTANTE de la corrida, no el inicio del día
--     (Codex f2 r2 P1): un WhatsApp de la 01:00 cuenta en la corrida de las 05:10.
--   · private.potencial_nivel_tras(nivel, días): la regla en UN solo lugar (≥10 → frío; ≥5 y
--     estrella → tibio; si no, igual). La usan el filtro de candidatos y el bucle (y la pantalla de
--     la fase 3 podrá usarla para «baja en N días»).
--   · private.potencial_caducar(p_hoy, p_corte, p_limite): recorre las marcas Estrella y Tibio de
--     leads activos y abiertos, de la más antigua a la más nueva, COMO MUCHO p_limite por corrida
--     (200; Codex f2 r2 P2: los candados que toma se sostienen hasta el final de la corrida, así que
--     el lote se acota y su duración se midió). NUNCA ESPERA (Codex f2 r1 F1, auditor P3-1/P3-2): por cada candidato intenta el
--     MISMO candado consultivo de la puerta de la fase 1 y la fila del lead en FOR SHARE SKIP LOCKED;
--     si alguno está ocupado, lo deja para la próxima corrida. Bajo los candados relee el lead
--     (activo y abierto) y la marca, recalcula y solo BAJA (origen 'caducidad'; marcado_por y
--     marcado_en intactos; evento inmutable con autor nulo). Idempotente: un día saltado se pone
--     al día al siguiente (la regla es acumulativa).
--   · pg_cron 'crm-potencial-lead-caducidad' a las 10:10 y 10:40 UTC (05:10 y 05:40 Lima) TODOS los
--     días (Codex f2 r1 F2): el domingo no cuenta como día, pero lo que se cumplió el sábado se
--     aplica el domingo de madrugada; la segunda pasada recoge lo que superó el límite de la
--     primera. Sin pg_cron (banco): aviso y no se programa.
--   · No mira la bandera: solo actúa sobre marcas que ya existen (con la bandera apagada no hay).
-- SUPUESTOS a confirmar con Miguel antes de encender la bandera (auditor P3-5): una Estrella llega a
--   Frío a los 10 días en total (no 5 + 10); el tiempo que el lead pasó cerrado o inactivo cuenta como
--   sin gestión; agendar una tarea o reasignar no reinicia el reloj.
-- RIESGO RESIDUAL: un contacto confirmado en el instante entre la relectura y el UPDATE no se ve
--   (los escritores de contactos no toman el candado consultivo); el analista vuelve a marcar.
-- CAPAS: núcleo en private, sin puerta: lo invoca pg_cron como postgres (BYPASSRLS). Sin EXECUTE
--   para la API.
-- REVERSA: supabase/scripts/potencial-lead/reversa-caducidad.sql (desprograma el job y quita las
--   funciones; los eventos 'caducidad' ya escritos se quedan: son historial inmutable).

begin;
set local lock_timeout = '5s';

-- ── 0 · Preflight ──────────────────────────────────────────────────────────────
do $preflight$
begin
  if (
    pg_catalog.to_regclass('crm.lead_potencial') is not null
    and pg_catalog.to_regclass('crm.lead_potencial_eventos') is not null
    and pg_catalog.to_regprocedure('crm.marcar_potencial_lead_fn(uuid,crm.nivel_potencial)') is not null
  ) is not true then
    raise exception 'PREFLIGHT potencial_caducidad: falta la fase 1 (20260930213647_crm_potencial_lead)';
  end if;

  if (
    pg_catalog.to_regprocedure('private.dias_lunes_a_sabado(date,date)') is null
    and pg_catalog.to_regprocedure('private.potencial_reloj(uuid,timestamp with time zone,timestamp with time zone)') is null
    and pg_catalog.to_regprocedure('private.potencial_nivel_tras(crm.nivel_potencial,integer)') is null
    and not exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
                    where n.nspname = 'private' and p.proname = 'potencial_caducar')
  ) is not true then
    raise exception 'PREFLIGHT potencial_caducidad: ya aplicada o aplicada a medias';
  end if;

  -- La caducidad y la marca comparten el protocolo de candado: ambos ayudantes de la fase 1
  -- deben seguir tomando el consultivo (hashtext('crm.lead_potencial'), hashtext(lead_id)).
  -- (Evidencia de texto: acredita que la llamada está en el cuerpo, no que se ejecute.)
  if (
    (select count(*) from pg_catalog.pg_proc p
      where p.oid in ('private.potencial_bloquear_lead(uuid)'::pg_catalog.regprocedure,
                      'private.potencial_marcar_nucleo(uuid,uuid,crm.nivel_potencial)'::pg_catalog.regprocedure)
        and pg_catalog.strpos(p.prosrc, 'pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(''crm.lead_potencial''), pg_catalog.hashtext(p_lead_id::text))') > 0) = 2
  ) is not true then
    raise exception 'PREFLIGHT potencial_caducidad: la fase 1 ya no usa el candado consultivo esperado';
  end if;

  -- El reloj depende de estos tipos de contacto: si el CHECK de crm.actividades cambió, revisar
  -- (política conservadora: también se niega ante un cambio equivalente, p. ej. reordenado).
  if (
    select pg_catalog.pg_get_constraintdef(c.oid) from pg_catalog.pg_constraint c
    where c.conrelid = 'crm.actividades'::pg_catalog.regclass and c.conname = 'actividades_tipo_check'
  ) is distinct from 'CHECK ((tipo = ANY (ARRAY[''llamada_realizada''::text, ''llamada_no_contestada''::text, ''whatsapp_enviado''::text, ''whatsapp_recibido''::text, ''reunion_realizada''::text, ''nota''::text, ''cambio_etapa''::text, ''reasignacion''::text, ''conversion''::text])))' then
    raise exception 'PREFLIGHT potencial_caducidad: cambió el catálogo de tipos de crm.actividades; revisar qué cuenta como gestión';
  end if;

  -- El job debe correr como postgres (BYPASSRLS) sobre esta base, con pg_cron en GMT (10:10 =
  -- 05:10 Lima); y no puede haber ya un job con su nombre.
  if pg_catalog.to_regclass('cron.job') is not null then
    if (
      current_user = 'postgres'
      and coalesce(pg_catalog.current_setting('cron.timezone', true), 'GMT') in ('GMT', 'UTC', 'Etc/UTC')
      and (select r.rolbypassrls from pg_catalog.pg_roles r where r.rolname = 'postgres')
    ) is not true then
      raise exception 'PREFLIGHT potencial_caducidad: el job quedaría con otro usuario, sin BYPASSRLS o con cron.timezone distinto de GMT (%)',
        pg_catalog.current_setting('cron.timezone', true);
    end if;
    if exists (select 1 from cron.job j where j.jobname = 'crm-potencial-lead-caducidad') then
      raise exception 'PREFLIGHT potencial_caducidad: ya existe un job crm-potencial-lead-caducidad';
    end if;
  end if;
end;
$preflight$;

-- ── 1 · Días completos de lunes a sábado ──────────────────────────────────────
create function private.dias_lunes_a_sabado(p_desde date, p_hasta date)
returns integer
language sql
immutable
security invoker
set search_path = ''
as $function$
  select coalesce((
    select pg_catalog.count(*)::integer
    from pg_catalog.generate_series((p_desde + 1)::timestamp, (p_hasta - 1)::timestamp, interval '1 day') d
    where pg_catalog.date_part('isodow', d) <> 7
  ), 0);
$function$;
comment on function private.dias_lunes_a_sabado(date, date) is
'Días COMPLETOS de lunes a sábado estrictamente entre p_desde y p_hasta (sin contar ninguna de las dos fechas; domingos fuera). 0 si no hay días entre medio. Reloj de la caducidad del potencial del lead.';

-- ── 2 · El reloj y la regla, en un solo lugar ─────────────────────────────────
create function private.potencial_reloj(p_lead_id uuid, p_marcado_en timestamptz, p_corte timestamptz)
returns timestamptz
language sql
stable
security invoker
set search_path = ''
as $function$
  select greatest(p_marcado_en, coalesce((
    select max(a.creado_en) from crm.actividades a
    where a.lead_id = p_lead_id
      and a.tipo in ('llamada_realizada', 'llamada_no_contestada', 'whatsapp_enviado',
                     'whatsapp_recibido', 'reunion_realizada')
      and a.creado_en <= p_corte), p_marcado_en));
$function$;
comment on function private.potencial_reloj(uuid, timestamptz, timestamptz) is
'Desde cuándo corre el reloj de la caducidad del potencial: lo más reciente entre la última marca humana y el último CONTACTO del lead hasta el instante p_corte inclusive (llamada realizada o no contestada, WhatsApp enviado o recibido, reunión realizada). Las notas no cuentan; un contacto con fecha futura no cuenta hasta su hora.';

create function private.potencial_nivel_tras(p_nivel crm.nivel_potencial, p_dias integer)
returns crm.nivel_potencial
language sql
immutable
security invoker
set search_path = ''
as $function$
  select case
    when p_dias >= 10 then 'frio'::crm.nivel_potencial
    when p_dias >= 5 and p_nivel = 'estrella' then 'tibio'::crm.nivel_potencial
    else p_nivel
  end;
$function$;
comment on function private.potencial_nivel_tras(crm.nivel_potencial, integer) is
'Regla de Miguel (30/09): con 10 o más días completos sin gestión (lunes a sábado) → frío; con 5 o más, una estrella → tibio; si no, el mismo nivel. Única fuente de la regla.';

-- ── 3 · Núcleo de la caducidad ────────────────────────────────────────────────
create function private.potencial_caducar(
  p_hoy date default (pg_catalog.now() at time zone 'America/Lima')::date,
  p_corte timestamptz default pg_catalog.now(),
  p_limite integer default 200
)
returns integer
language plpgsql
volatile
security invoker
set search_path = ''
set lock_timeout = '10s'
as $function$
declare
  v_lead uuid;
  v_activo boolean;
  v_etapa text;
  v_actual crm.lead_potencial;
  v_nuevo crm.nivel_potencial;
  v_n integer := 0;
begin
  if p_hoy is null or p_corte is null or p_limite is null or p_limite < 1 then
    raise exception 'Fecha, instante de corte y límite (≥ 1) requeridos' using errcode = '22023';
  end if;

  -- Candidatos SIN candado (barato), de la marca más antigua a la más nueva y como mucho p_limite:
  -- lo que no entra (o se salta por estar ocupado) se recoge en la próxima pasada.
  for v_lead in
    select p.lead_id
    from crm.lead_potencial p
    join crm.leads l on l.id = p.lead_id
    where p.nivel in ('estrella', 'tibio')
      and l.activo is true
      and l.etapa not in ('convertido', 'descartado')
      and private.potencial_nivel_tras(p.nivel, private.dias_lunes_a_sabado(
            (private.potencial_reloj(p.lead_id, p.marcado_en, p_corte) at time zone 'America/Lima')::date, p_hoy)) < p.nivel
    order by p.marcado_en, p.lead_id
    limit p_limite
  loop
    -- Mismo orden que la puerta de la fase 1 (consultivo y después la fila del lead), pero SIN
    -- esperar: si una marca o una escritura del lead está en vuelo, se salta hasta la próxima
    -- corrida. Así la tarea no forma ciclos de espera ni frena operaciones de los usuarios.
    continue when pg_catalog.pg_try_advisory_xact_lock(pg_catalog.hashtext('crm.lead_potencial'), pg_catalog.hashtext(v_lead::text)) is not true;

    select l.activo, l.etapa into v_activo, v_etapa
    from crm.leads l where l.id = v_lead
    for share skip locked;
    continue when (found and v_activo is true and v_etapa is not null
                   and v_etapa not in ('convertido', 'descartado')) is not true;

    -- Releído bajo los candados: una marca o un contacto confirmados mientras tanto cuentan.
    select p.* into v_actual from crm.lead_potencial p where p.lead_id = v_lead;
    continue when (v_actual.id is not null and v_actual.nivel in ('estrella', 'tibio')) is not true;

    v_nuevo := private.potencial_nivel_tras(v_actual.nivel, private.dias_lunes_a_sabado(
      (private.potencial_reloj(v_lead, v_actual.marcado_en, p_corte) at time zone 'America/Lima')::date, p_hoy));
    -- Solo baja (frio < tibio < estrella) y nunca escribe NULL.
    continue when (v_nuevo < v_actual.nivel) is not true;

    update crm.lead_potencial
       set nivel = v_nuevo, origen = 'caducidad'
     where lead_id = v_lead;
    insert into crm.lead_potencial_eventos (lead_id, nivel_anterior, nivel_nuevo, motivo, por, creado_en)
    values (v_lead, v_actual.nivel, v_nuevo, 'caducidad', null, pg_catalog.clock_timestamp());
    v_n := v_n + 1;
  end loop;

  return v_n;
end;
$function$;
comment on function private.potencial_caducar(date, timestamptz, integer) is
'Caducidad diaria del potencial del lead: Estrella → Tibio con 5 días completos (lunes a sábado) sin contacto ni marca hasta el instante de corte; Tibio → Frío con 10. Solo leads activos y abiertos, de la marca más antigua a la más nueva, como mucho p_limite por corrida. Nunca espera: intenta el candado consultivo de la marca y la fila del lead (SKIP LOCKED); si están ocupados, deja el lead para la próxima corrida. Relee bajo los candados, solo baja y deja evento inmutable (motivo caducidad, autor nulo). Devuelve cuántas marcas bajó. Idempotente. Lo invoca pg_cron (crm-potencial-lead-caducidad) como postgres. Sin EXECUTE para la API.';

-- ── 4 · Dueños y permisos ─────────────────────────────────────────────────────
alter function private.dias_lunes_a_sabado(date, date) owner to postgres;
alter function private.potencial_reloj(uuid, timestamptz, timestamptz) owner to postgres;
alter function private.potencial_nivel_tras(crm.nivel_potencial, integer) owner to postgres;
alter function private.potencial_caducar(date, timestamptz, integer) owner to postgres;
revoke all on function private.dias_lunes_a_sabado(date, date) from public, anon, authenticated, service_role;
revoke all on function private.potencial_reloj(uuid, timestamptz, timestamptz) from public, anon, authenticated, service_role;
revoke all on function private.potencial_nivel_tras(crm.nivel_potencial, integer) from public, anon, authenticated, service_role;
revoke all on function private.potencial_caducar(date, timestamptz, integer) from public, anon, authenticated, service_role;

-- ── 5 · Programación diaria (05:10 y 05:40 Lima, todos los días) ──────────────
do $cron$
begin
  if pg_catalog.to_regprocedure('cron.schedule(text,text,text)') is null then
    raise notice 'pg_cron no está disponible: no se programa la caducidad del potencial.';
    return;
  end if;
  perform cron.schedule(
    'crm-potencial-lead-caducidad',
    '10,40 10 * * *',  -- 10:10 y 10:40 GMT = 05:10 y 05:40 Lima, antes de la jornada
    'select private.potencial_caducar()'
  );
end;
$cron$;

-- ── 6 · Postflight ─────────────────────────────────────────────────────────────
do $postflight$
declare
  v_funciones pg_catalog.regprocedure[] := array[
    'private.dias_lunes_a_sabado(date,date)'::pg_catalog.regprocedure,
    'private.potencial_reloj(uuid,timestamp with time zone,timestamp with time zone)'::pg_catalog.regprocedure,
    'private.potencial_nivel_tras(crm.nivel_potencial,integer)'::pg_catalog.regprocedure,
    'private.potencial_caducar(date,timestamp with time zone,integer)'::pg_catalog.regprocedure
  ];
begin
  perform pg_catalog.set_config('search_path', '', true);

  if (
    (select count(*) from pg_catalog.pg_proc p
      where p.oid = any (v_funciones) and not p.prosecdef and p.proowner = 'postgres'::pg_catalog.regrole
        and p.proconfig is not null and p.proconfig @> array['search_path=""']::text[]
        and p.proacl is not null) = 4
    and not exists (select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
                    where p.oid = any (v_funciones) and a.grantee <> 'postgres'::pg_catalog.regrole)
    and exists (select 1 from pg_catalog.pg_proc p
                where p.oid = 'private.potencial_caducar(date,timestamp with time zone,integer)'::pg_catalog.regprocedure
                  and p.proconfig @> array['lock_timeout=10s']::text[])
  ) is not true then
    raise exception 'POSTFLIGHT potencial_caducidad: funciones sin la forma prevista (INVOKER, dueño postgres, search_path vacío, lock_timeout, sin EXECUTE de la API)';
  end if;

  -- Contrato del reloj y de la regla, a mano (no depende de la fecha de hoy).
  if (
    private.dias_lunes_a_sabado('2026-10-05', '2026-10-12') = 5
    and private.dias_lunes_a_sabado('2026-10-09', '2026-10-12') = 1
    and private.dias_lunes_a_sabado('2026-10-10', '2026-10-12') = 0
    and private.dias_lunes_a_sabado('2026-10-05', '2026-10-11') = 5
    and private.dias_lunes_a_sabado('2026-10-05', '2026-10-05') = 0
    and private.dias_lunes_a_sabado('2026-10-05', '2026-10-06') = 0
    and private.dias_lunes_a_sabado('2026-10-05', '2026-10-17') = 10
    and private.potencial_nivel_tras('estrella', 4) = 'estrella'
    and private.potencial_nivel_tras('estrella', 5) = 'tibio'
    and private.potencial_nivel_tras('estrella', 10) = 'frio'
    and private.potencial_nivel_tras('tibio', 9) = 'tibio'
    and private.potencial_nivel_tras('tibio', 10) = 'frio'
    and private.potencial_nivel_tras('frio', 0) = 'frio'
  ) is not true then
    raise exception 'POSTFLIGHT potencial_caducidad: el reloj o la regla no son los acordados';
  end if;

  -- Con pg_cron: UN solo job con ese nombre, activo, con horario, comando, usuario y base exactos.
  if pg_catalog.to_regclass('cron.job') is not null then
    if (
      (select count(*) from cron.job j where j.jobname = 'crm-potencial-lead-caducidad') = 1
      and (select count(*) from cron.job j
            where j.jobname = 'crm-potencial-lead-caducidad' and j.schedule = '10,40 10 * * *'
              and j.command = 'select private.potencial_caducar()' and j.active
              and j.username = 'postgres' and j.database = pg_catalog.current_database()) = 1
    ) is not true then
      raise exception 'POSTFLIGHT potencial_caducidad: el job crm-potencial-lead-caducidad no quedó programado como se esperaba';
    end if;
  end if;

  raise notice 'potencial_caducidad OK: reloj lunes a sábado, núcleo INVOKER que nunca espera, sin EXECUTE de la API, job %.',
    case when pg_catalog.to_regclass('cron.job') is null then '(sin pg_cron en esta base)' else 'programado' end;
end;
$postflight$;

commit;
