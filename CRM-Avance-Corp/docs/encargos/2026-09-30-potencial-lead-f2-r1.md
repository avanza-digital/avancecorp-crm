ROLE: SECONDARY_REVIEWER.
Do not modify files. Do not implement the task. Do not invoke Claude. Do not delegate to another coding agent. Do not create another review chain.

# Encargo de revisión — RONDA 1 (LEVEL 3: escritura automática de datos por pg_cron) · Potencial del lead, FASE 2

Eres el revisor secundario. Sin base de datos ni red: todo está transcrito abajo. Responde con VERDICT (APPROVE / CHANGES_REQUESTED), SUMMARY, FINDINGS P0–P3 con evidencia (archivo/línea/fragmento), riesgos y test gaps, NEXT ACTIONS y CONFIDENCE. Sin hallazgo sin evidencia. Tu tarea: REFUTAR.

## Negocio (reglas de Miguel, 30/09)
La marca de potencial del lead baja sola: Estrella → Tibio con 5 días sin gestión; Tibio → Frío con 10. Cuentan de lunes a sábado (domingo no). Cada gestión registrada reinicia el reloj; marcar también (fase 1 guarda `marcado_en`). Feriados: día normal (supuesto comunicado al dueño). La fase 1 (abajo, YA EN PRODUCCIÓN y revisada por ti en 2 rondas) creó las tablas, la puerta y el candado consultivo por lead.

## Decisiones a refutar
1. «Gestión» = los 5 tipos de contacto (índice existente `actividades_contacto_episodio_idx`: llamada_realizada, llamada_no_contestada, whatsapp_enviado, whatsapp_recibido, reunion_realizada). Las notas NO cuentan porque el sistema también las escribe (p. ej. `crm.anular_cierre_avance` deja una nota). Catálogo vivo de tipos (CHECK de crm.actividades): llamada_realizada, llamada_no_contestada, whatsapp_enviado, whatsapp_recibido, reunion_realizada, nota, cambio_etapa, reasignacion, conversion.
2. Días COMPLETOS estrictamente entre la fecha del reloj y hoy (la tarea corre 05:10 Lima: hoy no pasó). Fechas en America/Lima.
3. Candidatos sin candado (filtro con los mismos ayudantes), y por cada candidato: el MISMO consultivo que la puerta de la fase 1, relectura bajo el candado y recálculo con los mismos ayudantes.
4. La tarea NO mira la bandera `potencial_lead` (solo actúa sobre marcas existentes).
5. Solo leads activos y no convertidos/descartados; frío nunca cambia; un apagón de varios días baja de golpe (estrella → frío) con un solo evento.
6. `marcado_por` y `marcado_en` no cambian con la caducidad (marcado_en = última marca humana).
7. Un solo `select private.potencial_caducar()` por día = UNA transacción para todos los candidatos.

## Preguntas
a. ¿El reloj puede quedar mal por zona horaria (UTC del servidor vs Lima) o por la conversión date↔timestamp?
b. ¿Algún caso en que baje algo que no debía, o no baje (p. ej. contacto con `creado_en` futuro, reasignación, `marcado_en` posterior al último contacto)?
c. ¿El orden de candados con la puerta (consultivo + FOR SHARE del lead) o con escritores de crm.leads puede interbloquear? ¿Y el tamaño de una única transacción diaria?
d. ¿pre/postflight con falsos verdes o falsos rojos (CHECK por texto exacto, job por texto exacto)?
e. ¿Algo que la fase 3 (pantalla: «baja en N días») vaya a necesitar distinto?

## Evidencia (banco Docker propio, esquema de prod del 30/09, pg_cron activado)
- Ciclo: migración PASS (job `10 10 * * 1-6` / `select private.potencial_caducar()` / activo) → repetida se niega → reversa de fase 1 con la 2 puesta se niega → reversa f2 PASS (sin job) → repetida se niega → migración PASS → registrar ×2 idempotente → verificar OK.
- prueba-caducidad.sql (abajo): 41 de 41. Fase 1 sintética sin regresión: 75/75.
- prueba-concurrencia-caducidad.sh (abajo): 4/4; sin el consultivo en la tarea: 3 fallas (bajó una estrella recién re-marcada).
- Mutantes de lógica cazados: domingo cuenta (6 fallas), hoy incluido (9), nota es gestión (5), reloj sin contacto (7), umbral 4 (4), tibio a los 5 (8), cerrados también (3). Mutantes de la migración rechazados: EXECUTE abierto, horario sin `1-6`, regla distinta (postflight).
- Huella del CHECK medida igual en banco y producción.

## Archivos

### supabase/migrations/20260930235917_crm_potencial_lead_caducidad.sql (NUEVA)
```sql
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
--   · private.potencial_reloj(lead, marcado_en): lo más reciente entre la última marca humana y el
--     último CONTACTO del lead en crm.actividades (los 5 tipos del índice
--     actividades_contacto_episodio_idx: llamada realizada o no contestada, WhatsApp enviado o
--     recibido, reunión realizada). Las notas no cuentan: el sistema también escribe notas (p. ej.
--     al anular un cierre).
--   · private.potencial_nivel_tras(nivel, días): la regla en UN solo lugar (≥10 → frío; ≥5 y
--     estrella → tibio; si no, igual). La usan el filtro de candidatos y el bucle (y la pantalla de
--     la fase 3 podrá usarla para «baja en N días»).
--   · private.potencial_caducar(p_hoy): recorre las marcas Estrella y Tibio de leads activos y
--     abiertos y aplica la regla con esos ayudantes. Si toca bajar,
--     toma el MISMO candado consultivo que la puerta de la fase 1, vuelve a leer bajo el candado,
--     baja el nivel (origen 'caducidad', marcado_por y marcado_en intactos) y deja un evento
--     inmutable con motivo 'caducidad' y autor nulo (lo hizo el sistema). Idempotente.
--   · pg_cron 'crm-potencial-lead-caducidad' a las 10:10 UTC (05:10 Lima) de lunes a sábado.
--     Sin pg_cron (banco): aviso y no se programa.
--   · No mira la bandera: solo actúa sobre marcas que ya existen (con la bandera apagada no hay).
-- CAPAS: núcleo en private, sin puerta: lo invoca pg_cron como postgres. Sin EXECUTE para la API.
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
    and pg_catalog.to_regprocedure('private.potencial_reloj(uuid,timestamp with time zone)') is null
    and pg_catalog.to_regprocedure('private.potencial_nivel_tras(crm.nivel_potencial,integer)') is null
    and pg_catalog.to_regprocedure('private.potencial_caducar(date)') is null
  ) is not true then
    raise exception 'PREFLIGHT potencial_caducidad: ya aplicada o aplicada a medias';
  end if;

  -- La caducidad y la marca comparten el protocolo de candado: ambos ayudantes de la fase 1
  -- deben seguir tomando el consultivo (hashtext('crm.lead_potencial'), hashtext(lead_id)).
  if (
    (select count(*) from pg_catalog.pg_proc p
      where p.oid in ('private.potencial_bloquear_lead(uuid)'::pg_catalog.regprocedure,
                      'private.potencial_marcar_nucleo(uuid,uuid,crm.nivel_potencial)'::pg_catalog.regprocedure)
        and pg_catalog.strpos(p.prosrc, 'pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(''crm.lead_potencial''), pg_catalog.hashtext(p_lead_id::text))') > 0) = 2
  ) is not true then
    raise exception 'PREFLIGHT potencial_caducidad: la fase 1 ya no usa el candado consultivo esperado';
  end if;

  -- El reloj depende de estos tipos de contacto: si el CHECK de crm.actividades cambió, revisar.
  if (
    select pg_catalog.pg_get_constraintdef(c.oid) from pg_catalog.pg_constraint c
    where c.conrelid = 'crm.actividades'::pg_catalog.regclass and c.conname = 'actividades_tipo_check'
  ) is distinct from 'CHECK ((tipo = ANY (ARRAY[''llamada_realizada''::text, ''llamada_no_contestada''::text, ''whatsapp_enviado''::text, ''whatsapp_recibido''::text, ''reunion_realizada''::text, ''nota''::text, ''cambio_etapa''::text, ''reasignacion''::text, ''conversion''::text])))' then
    raise exception 'PREFLIGHT potencial_caducidad: cambió el catálogo de tipos de crm.actividades; revisar qué cuenta como gestión';
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
create function private.potencial_reloj(p_lead_id uuid, p_marcado_en timestamptz)
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
                     'whatsapp_recibido', 'reunion_realizada')), p_marcado_en));
$function$;
comment on function private.potencial_reloj(uuid, timestamptz) is
'Desde cuándo corre el reloj de la caducidad del potencial: lo más reciente entre la última marca humana y el último CONTACTO del lead (llamada realizada o no contestada, WhatsApp enviado o recibido, reunión realizada). Las notas no cuentan.';

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
create function private.potencial_caducar(p_hoy date default (pg_catalog.now() at time zone 'America/Lima')::date)
returns integer
language plpgsql
volatile
security invoker
set search_path = ''
as $function$
declare
  v_lead uuid;
  v_actual crm.lead_potencial;
  v_nuevo crm.nivel_potencial;
  v_n integer := 0;
begin
  if p_hoy is null then
    raise exception 'Fecha de referencia requerida' using errcode = '22023';
  end if;

  -- Candidatos SIN candado (barato); solo los que parecen tocar se bloquean y se releen. Así la
  -- transacción no acumula un candado consultivo por cada marca viva.
  for v_lead in
    select p.lead_id
    from crm.lead_potencial p
    join crm.leads l on l.id = p.lead_id
    where p.nivel in ('estrella', 'tibio')
      and l.activo is true
      and l.etapa not in ('convertido', 'descartado')
      and private.potencial_nivel_tras(p.nivel, private.dias_lunes_a_sabado(
            (private.potencial_reloj(p.lead_id, p.marcado_en) at time zone 'America/Lima')::date, p_hoy)) <> p.nivel
    order by p.lead_id
  loop
    -- Mismo candado que la puerta de la fase 1: una marca en vuelo termina antes o espera.
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.lead_potencial'), pg_catalog.hashtext(v_lead::text));

    select p.* into v_actual from crm.lead_potencial p where p.lead_id = v_lead;
    continue when v_actual.id is null or v_actual.nivel not in ('estrella', 'tibio');

    -- Releído bajo el candado: una marca o un contacto confirmados mientras tanto cuentan.
    v_nuevo := private.potencial_nivel_tras(v_actual.nivel, private.dias_lunes_a_sabado(
      (private.potencial_reloj(v_lead, v_actual.marcado_en) at time zone 'America/Lima')::date, p_hoy));
    continue when v_nuevo = v_actual.nivel;

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
comment on function private.potencial_caducar(date) is
'Caducidad diaria del potencial del lead: Estrella → Tibio con 5 días completos (lunes a sábado) sin contacto ni marca; Tibio → Frío con 10. Solo leads activos y abiertos. Toma el candado consultivo de la marca, relee y deja evento inmutable (motivo caducidad, autor nulo). Devuelve cuántas marcas bajó. Idempotente. Lo invoca pg_cron (crm-potencial-lead-caducidad). Sin EXECUTE para la API.';

-- ── 4 · Dueños y permisos ─────────────────────────────────────────────────────
alter function private.dias_lunes_a_sabado(date, date) owner to postgres;
alter function private.potencial_reloj(uuid, timestamptz) owner to postgres;
alter function private.potencial_nivel_tras(crm.nivel_potencial, integer) owner to postgres;
alter function private.potencial_caducar(date) owner to postgres;
revoke all on function private.dias_lunes_a_sabado(date, date) from public, anon, authenticated, service_role;
revoke all on function private.potencial_reloj(uuid, timestamptz) from public, anon, authenticated, service_role;
revoke all on function private.potencial_nivel_tras(crm.nivel_potencial, integer) from public, anon, authenticated, service_role;
revoke all on function private.potencial_caducar(date) from public, anon, authenticated, service_role;

-- ── 5 · Programación diaria (05:10 Lima, lunes a sábado) ──────────────────────
do $cron$
begin
  if pg_catalog.to_regprocedure('cron.schedule(text,text,text)') is null then
    raise notice 'pg_cron no está disponible: no se programa la caducidad del potencial.';
    return;
  end if;
  perform cron.schedule(
    'crm-potencial-lead-caducidad',
    '10 10 * * 1-6',  -- 10:10 UTC = 05:10 Lima, antes de que empiece la jornada
    'select private.potencial_caducar()'
  );
end;
$cron$;

-- ── 6 · Postflight ─────────────────────────────────────────────────────────────
do $postflight$
declare
  v_funciones pg_catalog.regprocedure[] := array[
    'private.dias_lunes_a_sabado(date,date)'::pg_catalog.regprocedure,
    'private.potencial_reloj(uuid,timestamp with time zone)'::pg_catalog.regprocedure,
    'private.potencial_nivel_tras(crm.nivel_potencial,integer)'::pg_catalog.regprocedure,
    'private.potencial_caducar(date)'::pg_catalog.regprocedure
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
  ) is not true then
    raise exception 'POSTFLIGHT potencial_caducidad: funciones sin la forma prevista (INVOKER, dueño postgres, search_path vacío, sin EXECUTE de la API)';
  end if;

  -- Contrato del reloj, a mano (no depende de la fecha de hoy): lunes → lunes siguiente = 5 días
  -- completos (mar-sáb); viernes → lunes = 1 (sábado); sábado → lunes = 0 (domingo no cuenta);
  -- mismo día o día siguiente = 0.
  if (
    private.dias_lunes_a_sabado('2026-10-05', '2026-10-12') = 5
    and private.dias_lunes_a_sabado('2026-10-09', '2026-10-12') = 1
    and private.dias_lunes_a_sabado('2026-10-10', '2026-10-12') = 0
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
    raise exception 'POSTFLIGHT potencial_caducidad: el conteo de días de lunes a sábado no es el acordado';
  end if;

  -- Con pg_cron: el job existe, activo, con su horario y su comando exactos.
  if pg_catalog.to_regclass('cron.job') is not null then
    if (
      (select count(*) from cron.job j
        where j.jobname = 'crm-potencial-lead-caducidad' and j.schedule = '10 10 * * 1-6'
          and j.command = 'select private.potencial_caducar()' and j.active) = 1
    ) is not true then
      raise exception 'POSTFLIGHT potencial_caducidad: el job crm-potencial-lead-caducidad no quedó programado como se esperaba';
    end if;
  end if;

  raise notice 'potencial_caducidad OK: reloj lunes a sábado, núcleo INVOKER sin EXECUTE de la API, job % .',
    case when pg_catalog.to_regclass('cron.job') is null then '(sin pg_cron en esta base)' else 'programado' end;
end;
$postflight$;

commit;

```

### supabase/scripts/potencial-lead/reversa-caducidad.sql
```sql
-- REVERSA de 20260930235917_crm_potencial_lead_caducidad (fase 2).
-- Desprograma el job (si existe) y quita las dos funciones. Los eventos con motivo 'caducidad' ya
-- escritos SE QUEDAN: son historial inmutable, y los niveles bajados no se «suben» solos (una
-- persona vuelve a marcar si quiere). Conserva la fila de schema_migrations: anotarlo en
-- MIGRACIONES.md. Debe correr ANTES que la reversa de la fase 1.
begin;
set local lock_timeout = '5s';
do $chk$
begin
  if (
    pg_catalog.to_regprocedure('private.potencial_caducar(date)') is not null
    and pg_catalog.to_regprocedure('private.dias_lunes_a_sabado(date,date)') is not null
  ) is not true then
    raise exception 'REVERSA potencial_caducidad: la fase 2 no está aplicada';
  end if;
  if pg_catalog.to_regprocedure('cron.unschedule(text)') is not null
     and exists (select 1 from cron.job where jobname = 'crm-potencial-lead-caducidad') then
    perform cron.unschedule('crm-potencial-lead-caducidad');
  end if;
end;
$chk$;

drop function private.potencial_caducar(date);
drop function private.potencial_nivel_tras(crm.nivel_potencial, integer);
drop function private.potencial_reloj(uuid, timestamptz);
drop function private.dias_lunes_a_sabado(date, date);

do $post$
begin
  if (
    pg_catalog.to_regprocedure('private.potencial_caducar(date)') is null
    and pg_catalog.to_regprocedure('private.potencial_nivel_tras(crm.nivel_potencial,integer)') is null
    and pg_catalog.to_regprocedure('private.potencial_reloj(uuid,timestamp with time zone)') is null
    and pg_catalog.to_regprocedure('private.dias_lunes_a_sabado(date,date)') is null
    and (pg_catalog.to_regclass('cron.job') is null
         or not exists (select 1 from cron.job where jobname = 'crm-potencial-lead-caducidad'))
  ) is not true then
    raise exception 'REVERSA potencial_caducidad: quedaron funciones o el job';
  end if;
  raise notice 'REVERSA potencial_caducidad OK: sin job ni funciones (el historial se conserva).';
end;
$post$;
commit;

```

### supabase/scripts/potencial-lead/prueba-caducidad.sql
```sql
-- Prueba sintética de 20260930235917_crm_potencial_lead_caducidad (fase 2).
-- SOLO en un banco, como supabase_admin, en UNA transacción que termina en raise (no deja nada).
-- Calendario simulado (hora de Lima): lunes 2026-10-05 10:00 se marcan los leads. Fechas clave:
-- sáb 10-10, lun 10-12, vie 10-16, sáb 10-17, lun 10-19. Los domingos 10-11 y 10-18 no cuentan.
begin;
set local lock_timeout = '5s';

create temp table act (k text primary key, id uuid not null default gen_random_uuid()) on commit drop;
insert into act (k) values ('S1'), ('V1');
create temp table lds (k text primary key, id uuid not null default gen_random_uuid()) on commit drop;
insert into lds (k) values ('A'), ('B'), ('C'), ('D'), ('E'), ('F'), ('G'), ('H'), ('I'), ('J');
create temp table res (n serial, caso text, esperado text, obtenido text) on commit drop;

create function pg_temp.a(p_k text) returns uuid language sql as $$ select id from act where k = p_k $$;
create function pg_temp.l(p_k text) returns uuid language sql as $$ select id from lds where k = p_k $$;
create function pg_temp.esperar(p_caso text, p_esperado text, p_obtenido text) returns void language sql as $$
  insert into res (caso, esperado, obtenido) values (p_caso, p_esperado, coalesce(p_obtenido, '(null)'))
$$;
create function pg_temp.nivel(p_k text) returns text language sql as $$
  select p.nivel::text || '/' || p.origen from crm.lead_potencial p where p.lead_id = pg_temp.l(p_k)
$$;
create function pg_temp.historial(p_k text) returns text language sql as $$
  select string_agg(coalesce(e.nivel_anterior::text, 'null') || '>' || e.nivel_nuevo || ':' || e.motivo
                    || ':' || coalesce((select k from act where id = e.por), 'sistema'), ',' order by e.orden)
  from crm.lead_potencial_eventos e where e.lead_id = pg_temp.l(p_k)
$$;
create function pg_temp.lima(p_texto text) returns timestamptz language sql as $$
  select (p_texto::timestamp at time zone 'America/Lima')
$$;

-- Mundo sin disparadores: un supervisor, un analista y 9 leads marcados el lunes 10-05 10:00 Lima.
set local session_replication_role = replica;
insert into auth.users (id, email) select id, lower(k) || '@caducidad.banco' from act;
insert into public.perfiles (id, nombre_completo, rol, activo) select id, 'CADUCIDAD ' || k, 'analista', true from act;
insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo) values
  (pg_temp.a('S1'), 'supervisor', null, true),
  (pg_temp.a('V1'), 'vendedor', pg_temp.a('S1'), true);
insert into crm.leads (id, nombre_completo, telefono, origen, monto_estimado, moneda, etapa, vendedor_id, activo, motivo_descarte)
select pg_temp.l(k), 'CADUCIDAD ' || k, '+5198766' || lpad((row_number() over (order by k))::text, 4, '0'), 'landing', 10000, 'PEN',
       case k when 'G' then 'convertido' else 'contactado' end, pg_temp.a('V1'), k <> 'H', null
from lds;
insert into crm.lead_potencial (lead_id, nivel, origen, marcado_por, marcado_en)
select pg_temp.l(k), (case k when 'E' then 'tibio' when 'F' then 'frio' else 'estrella' end)::crm.nivel_potencial,
       'manual', pg_temp.a('V1'), pg_temp.lima('2026-10-05 10:00')
from lds;
-- B: un CONTACTO el jueves 10-08 reinicia el reloj. C: una NOTA el jueves no lo reinicia.
insert into crm.actividades (lead_id, tipo, detalle, creado_por, creado_en) values
  (pg_temp.l('B'), 'llamada_no_contestada', 'prueba de caducidad', pg_temp.a('V1'), pg_temp.lima('2026-10-08 15:00')),
  (pg_temp.l('C'), 'nota', 'nota de sistema de prueba', null, pg_temp.lima('2026-10-08 15:00')),
  (pg_temp.l('J'), 'whatsapp_enviado', 'prueba de caducidad', pg_temp.a('V1'), pg_temp.lima('2026-10-09 18:00'));
set local session_replication_role = origin;

do $prueba$
declare
  v_n integer;
  v_estado text;
begin
  -- ── El reloj (contrato acordado) ──
  perform pg_temp.esperar('lun → lun siguiente = 5 días (mar-sáb)', '5', private.dias_lunes_a_sabado('2026-10-05', '2026-10-12')::text);
  perform pg_temp.esperar('vie → lun = 1 (solo sábado)', '1', private.dias_lunes_a_sabado('2026-10-09', '2026-10-12')::text);
  perform pg_temp.esperar('sáb → lun = 0 (domingo no cuenta)', '0', private.dias_lunes_a_sabado('2026-10-10', '2026-10-12')::text);
  perform pg_temp.esperar('lun → sáb de la otra semana = 10', '10', private.dias_lunes_a_sabado('2026-10-05', '2026-10-17')::text);
  perform pg_temp.esperar('regla: estrella con 4 días sigue', 'estrella', private.potencial_nivel_tras('estrella', 4)::text);
  perform pg_temp.esperar('regla: estrella con 5 → tibio', 'tibio', private.potencial_nivel_tras('estrella', 5)::text);
  perform pg_temp.esperar('regla: estrella con 10 → frío', 'frio', private.potencial_nivel_tras('estrella', 10)::text);
  perform pg_temp.esperar('regla: tibio con 9 sigue', 'tibio', private.potencial_nivel_tras('tibio', 9)::text);
  perform pg_temp.esperar('regla: tibio con 10 → frío', 'frio', private.potencial_nivel_tras('tibio', 10)::text);
  perform pg_temp.esperar('reloj de J: el WhatsApp del viernes', '2026-10-09 18:00', (
    select to_char(private.potencial_reloj(p.lead_id, p.marcado_en) at time zone 'America/Lima', 'YYYY-MM-DD HH24:MI')
    from crm.lead_potencial p where p.lead_id = pg_temp.l('J')));
  perform pg_temp.esperar('reloj de C: la nota NO lo mueve', '2026-10-05 10:00', (
    select to_char(private.potencial_reloj(p.lead_id, p.marcado_en) at time zone 'America/Lima', 'YYYY-MM-DD HH24:MI')
    from crm.lead_potencial p where p.lead_id = pg_temp.l('C')));
  perform pg_temp.esperar('hasta antes que desde = 0', '0', private.dias_lunes_a_sabado('2026-10-12', '2026-10-05')::text);
  begin
    perform private.potencial_caducar(null);
    perform pg_temp.esperar('fecha nula', '22023', 'ok');
  exception when others then
    perform pg_temp.esperar('fecha nula', '22023', sqlstate);
  end;

  -- ── Sábado 10-10: 4 días completos (mar-vie) → nadie baja ──
  v_n := private.potencial_caducar('2026-10-10');
  perform pg_temp.esperar('sáb 10-10: no baja nadie', '0', v_n::text);
  perform pg_temp.esperar('A sigue estrella el sábado', 'estrella/manual', pg_temp.nivel('A'));

  -- ── Lunes 10-12: 5 días (mar-sáb) ──
  v_n := private.potencial_caducar('2026-10-12');
  perform pg_temp.esperar('lun 10-12: bajan A, C, D e I (B tuvo contacto; E es tibio)', '4', v_n::text);
  perform pg_temp.esperar('A baja a tibio por caducidad', 'tibio/caducidad', pg_temp.nivel('A'));
  perform pg_temp.esperar('A: evento de sistema estrella>tibio', 'estrella>tibio:caducidad:sistema', pg_temp.historial('A'));
  perform pg_temp.esperar('A: marcado_por y marcado_en intactos', 'V1|2026-10-05 10:00', (
    select (select k from act where id = p.marcado_por) || '|' || to_char(p.marcado_en at time zone 'America/Lima', 'YYYY-MM-DD HH24:MI')
    from crm.lead_potencial p where p.lead_id = pg_temp.l('A')));
  perform pg_temp.esperar('B: el contacto del jueves reinicia el reloj (sigue estrella)', 'estrella/manual', pg_temp.nivel('B'));
  perform pg_temp.esperar('C: una nota no es gestión (baja)', 'tibio/caducidad', pg_temp.nivel('C'));
  perform pg_temp.esperar('E: un tibio no baja con 5 días', 'tibio/manual', pg_temp.nivel('E'));
  perform pg_temp.esperar('F: frío no cambia', 'frio/manual', pg_temp.nivel('F'));
  perform pg_temp.esperar('G: lead convertido no se toca', 'estrella/manual', pg_temp.nivel('G'));
  perform pg_temp.esperar('H: lead inactivo no se toca', 'estrella/manual', pg_temp.nivel('H'));

  -- ── Idempotente: correr dos veces el mismo día no hace nada más ──
  v_n := private.potencial_caducar('2026-10-12');
  perform pg_temp.esperar('lun 10-12 otra vez: 0', '0', v_n::text);
  perform pg_temp.esperar('A: un solo evento', 'estrella>tibio:caducidad:sistema', pg_temp.historial('A'));

  -- ── I: el analista vuelve a marcar estrella el martes 10-13: el reloj arranca de nuevo ──
  update crm.lead_potencial set nivel = 'estrella', origen = 'manual', marcado_en = pg_temp.lima('2026-10-13 10:00')
   where lead_id = pg_temp.l('I');

  -- ── Viernes 10-16: B lleva 6 días desde su contacto (vie, sáb, lun-jue) ──
  v_n := private.potencial_caducar('2026-10-16');
  perform pg_temp.esperar('vie 10-16: bajan B y J', '2', v_n::text);
  perform pg_temp.esperar('J (WhatsApp del viernes 10-09: 5 días) baja a tibio', 'estrella>tibio:caducidad:sistema', pg_temp.historial('J'));
  perform pg_temp.esperar('B baja a tibio', 'tibio/caducidad', pg_temp.nivel('B'));
  perform pg_temp.esperar('I re-marcado el martes sigue estrella', 'estrella/manual', pg_temp.nivel('I'));

  -- ── Sábado 10-17: 10 días desde el lunes 10-05 ──
  v_n := private.potencial_caducar('2026-10-17');
  perform pg_temp.esperar('sáb 10-17: bajan a frío A, C, D y E', '4', v_n::text);
  perform pg_temp.esperar('J sigue tibio el sábado (6 días desde su contacto; con el reloj de la marca serían 10)', 'tibio/caducidad', pg_temp.nivel('J'));
  perform pg_temp.esperar('A: tibio → frío', 'estrella>tibio:caducidad:sistema,tibio>frio:caducidad:sistema', pg_temp.historial('A'));
  perform pg_temp.esperar('D: estrella → tibio → frío', 'estrella>tibio:caducidad:sistema,tibio>frio:caducidad:sistema', pg_temp.historial('D'));
  perform pg_temp.esperar('E: tibio manual → frío', 'tibio>frio:caducidad:sistema', pg_temp.historial('E'));
  perform pg_temp.esperar('B (tibio desde el viernes, reloj del jueves 10-08) sigue tibio', 'tibio/caducidad', pg_temp.nivel('B'));
  perform pg_temp.esperar('I (re-marcado 10-13) sigue estrella', 'estrella/manual', pg_temp.nivel('I'));

  -- ── Un apagón de la tarea: estrella sin tocar 11 días baja DE GOLPE a frío, con un solo evento ──
  update crm.lead_potencial set nivel = 'estrella', origen = 'manual', marcado_en = pg_temp.lima('2026-10-05 10:00')
   where lead_id = pg_temp.l('F');
  v_n := private.potencial_caducar('2026-10-19');
  perform pg_temp.esperar('lun 10-19: F estrella de 11 días va directo a frío', 'frio/caducidad', pg_temp.nivel('F'));
  perform pg_temp.esperar('F: un solo evento estrella>frio', 'estrella>frio:caducidad:sistema', pg_temp.historial('F'));

  -- ── Auditoría: las bajadas dejaron rastro sin autor humano ──
  perform pg_temp.esperar('bitácora de caducidad en public.audit_log', 'true', (
    select (count(*) > 0)::text from public.audit_log a
    where a.tabla = 'crm.lead_potencial_eventos' and a.usuario_id is null
      and (a.data_despues ->> 'lead_id')::uuid in (select id from lds)));

  -- ── Veredicto (el raise deshace todo) ──
  select count(*) into v_n from res where esperado is distinct from obtenido;
  if v_n = 0 then
    raise exception 'CADUCIDAD potencial_lead: % de % OK', (select count(*) from res), (select count(*) from res) using errcode = 'P0001';
  else
    raise exception 'CADUCIDAD potencial_lead: % FALLAS de %: %', v_n, (select count(*) from res),
      (select string_agg(n || ' ' || caso || ' → esperado ' || esperado || ', obtenido ' || obtenido, ' | ' order by n)
       from res where esperado is distinct from obtenido) using errcode = 'P0001';
  end if;
end;
$prueba$;
rollback;

```

### supabase/scripts/potencial-lead/prueba-concurrencia-caducidad.sh
```bash
#!/usr/bin/env bash
# Prueba de CONCURRENCIA de 20260930235917_crm_potencial_lead_caducidad (fase 2).
# SOLO en el banco Docker propio. Una marca del analista en vuelo (tiene el candado consultivo del
# lead y reinicia marcado_en) se cruza con la tarea diaria. Esperado: la tarea ESPERA el candado,
# relee y no baja la estrella recién confirmada.
#   BANCO_CONTENEDOR=avancecorp-potencial-20260930 bash prueba-concurrencia-caducidad.sh
set -euo pipefail
C="${BANCO_CONTENEDOR:-avancecorp-potencial-20260930}"
psql_as() { local u="$1"; shift; docker exec -i -e PGPASSWORD=postgres "$C" psql -U "$u" -h 127.0.0.1 -d postgres -v ON_ERROR_STOP=1 -qAt "$@"; }
V1=00000000-0000-4000-8000-00000000d0a1; S1=00000000-0000-4000-8000-00000000d0b1
L1=00000000-0000-4000-8000-00000000d0c1
ok=0; mal=0
esperar() { if [[ "$3" =~ $2 ]]; then echo "  ✓ $1"; ok=$((ok+1)); else echo "  ✗ $1 — esperado /$2/, obtenido: $3"; mal=$((mal+1)); fi; }
limpiar() {
  psql_as supabase_admin <<SQL
set session_replication_role = replica;
delete from crm.lead_potencial_eventos where lead_id = '$L1';
delete from crm.lead_potencial where lead_id = '$L1';
delete from crm.leads where id = '$L1';
delete from crm.equipo where perfil_id in ('$V1','$S1');
delete from public.perfiles where id in ('$V1','$S1');
delete from auth.users where id in ('$V1','$S1');
SQL
}
limpiar
psql_as supabase_admin <<SQL
set session_replication_role = replica;
insert into auth.users (id, email) values ('$V1','dv1@caducidad.banco'),('$S1','ds1@caducidad.banco');
insert into public.perfiles (id, nombre_completo, rol, activo) values ('$V1','CONC CAD V1','analista',true),('$S1','CONC CAD S1','analista',true);
insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo) values ('$S1','supervisor',null,true),('$V1','vendedor','$S1',true);
insert into crm.leads (id, nombre_completo, telefono, origen, monto_estimado, moneda, etapa, vendedor_id, activo)
  values ('$L1','CONC CAD L1','+51987669001','landing',50000,'PEN','contactado','$V1',true);
insert into crm.lead_potencial (lead_id, nivel, origen, marcado_por, marcado_en)
  values ('$L1','estrella','manual','$V1', '2026-10-05 10:00'::timestamp at time zone 'America/Lima');
SQL

echo "A · la tarea diaria se cruza con una re-marca en vuelo"
( psql_as postgres -c "begin; select pg_advisory_xact_lock(hashtext('crm.lead_potencial'), hashtext('$L1')); update crm.lead_potencial set marcado_en = '2026-10-12 09:00'::timestamp at time zone 'America/Lima', origen = 'manual' where lead_id = '$L1'; select pg_sleep(3); commit;" >/dev/null ) &
sleep 1
t0=$(date +%s%N); r=$(psql_as postgres -c "select private.potencial_caducar('2026-10-12')" 2>&1 | tail -1); t1=$(date +%s%N); wait
esperar "la tarea no baja la estrella re-marcada (0 cambios)" '^0$' "$r"
esperar "la tarea esperó el candado (≥ 1,5 s)" '^1$' "$(( (t1 - t0) >= 1500000000 ? 1 : 0 ))"
esperar "el lead sigue estrella manual" '^estrella\|manual$' "$(psql_as postgres -c "select nivel || '|' || origen from crm.lead_potencial where lead_id = '$L1'")"
esperar "sin eventos de caducidad" '^0$' "$(psql_as postgres -c "select count(*) from crm.lead_potencial_eventos where lead_id = '$L1'")"

limpiar
echo "CONCURRENCIA caducidad: $ok OK, $mal FALLAS"
[ "$mal" -eq 0 ]

```

### Contexto: fase 1 YA EN PRODUCCIÓN (supabase/migrations/20260930213647_crm_potencial_lead.sql)
```sql
-- 20260930213647_crm_potencial_lead.sql
--
-- Potencial del lead: Frío · Tibio · Estrella. FASE 1 del plan aprobado por Miguel el
-- 30/09/2026 («HAZLO»). Nota del vault: «Potencial del lead - Frio Tibio Estrella (2026-09-30)».
-- Diseño visual aprobado: pieza CRM-05 del UI Playground.
--
-- QUÉ HACE
--   · Tipo crm.nivel_potencial ('frio','tibio','estrella').
--   · crm.lead_potencial: el nivel VIGENTE de cada lead (una fila por lead, viaja con el lead
--     si se reasigna). Es tabla propia y NO columnas de crm.leads: todo UPDATE de crm.leads
--     pasa por ~20 disparadores y private.leads_before_update reescribe actualizado_en, que es
--     la llave de orden de la cartera (leads_orden_cartera_idx) y despierta el SLA. Marcar no
--     debe reordenar la cartera ni tocar plazos.
--   · crm.lead_potencial_eventos: historial INMUTABLE (solo INSERT) de cada cambio. NO usa
--     crm.actividades: marcar no es una gestión (no reinicia SLA ni suma en métricas).
--   · Puerta crm.marcar_potencial_lead_fn(uuid, crm.nivel_potencial): solo el analista dueño
--     del lead o su supervisor (su subárbol, y el lead parqueado en su bandeja, que solo marca
--     un supervisor). Gerencia, Coordinación, Directorio y cualquier otro rol: 42501. Lead
--     ajeno, inactivo o inexistente: P0002 (no se distingue, para no revelar que existe). Lead
--     convertido o descartado: 22023. Volver a marcar el mismo nivel es válido (reinicia el
--     reloj de la caducidad de la fase 2 y deja su evento), salvo el doble clic: la misma
--     persona, mismo nivel, dentro de 60 s, no escribe nada nuevo.
--   · Bandera 'potencial_lead' en crm.multiempresa_flags, APAGADA: la puerta autoriza y
--     después se niega con 55000 hasta que la fase 3 (pantalla) la encienda.
--
-- CAPAS: puerta DEFINER (sesión, rol, candados, ámbito, bandera; delega) → núcleo
--   private.potencial_marcar_nucleo (INVOKER: estado + evento, atómico) → tablas. Ayudantes
--   privados INVOKER sin EXECUTE para ningún rol de la API: potencial_bloquear_lead (candado
--   consultivo por lead + FOR SHARE de la fila del lead) y potencial_rechazo (ámbito).
-- CONCURRENCIA (Codex r1 F1, r2 R2-1): la autorización decisiva se evalúa DESPUÉS de bloquear la
--   fila del lead (FOR SHARE: una reasignación o un cierre en vuelo termina antes, o espera a que
--   la marca termine); sin fila bloqueada (inexistente o aún sin confirmar) se rechaza. La fase 2
--   (caducidad) debe tomar el MISMO candado consultivo (hashtext('crm.lead_potencial'),
--   hashtext(lead_id)) antes de escribir. Riesgo residual documentado: una baja o un cambio de
--   jerarquía en crm.equipo confirmado en el mismo instante no se serializa con la marca (la marca
--   queda, y el actor ya no puede usarla ni verla).
-- SECURITY DEFINER, justificación: las tablas no dan INSERT/UPDATE a nadie de la API (una
--   marca no se escribe a mano por PostgREST) y la policy leads_update deja pasar a gerencia,
--   que aquí NO marca. La puerta verifica rol y ámbito de forma explícita con private.rol_crm y
--   private.vendedor_ids_visibles, los mismos ayudantes de leads_select/leads_update (el
--   preflight fija su identidad por md5 de cuerpo, DEFINER, volatilidad, configuración y dueño).
-- LECTURA: RLS ON con policy SELECT (exists sobre crm.leads, cuya RLS decide) como segundo
--   candado, pero SIN grant a authenticated: por la regla de 4 capas la pantalla no lee tablas;
--   la fase 3 leerá la marca por una puerta crm.* (auditor-rls r1). anon y service_role: nada.
-- SIN negocio_id: ninguna tabla del esquema crm lo tiene (convención del CRM; la regla de 4
--   capas lo reconoce como deuda del CRM actual). Nombres de tiempo en español (creado_en).
-- REVERSA: supabase/scripts/potencial-lead/reversa.sql (solo con las tablas vacías).

begin;
set local lock_timeout = '5s';

-- ── 0 · Preflight ──────────────────────────────────────────────────────────────
do $preflight$
declare
  v_md5_rol text;
  v_md5_visibles text;
begin
  if (
    pg_catalog.to_regtype('crm.nivel_potencial') is null
    and pg_catalog.to_regclass('crm.lead_potencial') is null
    and pg_catalog.to_regclass('crm.lead_potencial_eventos') is null
    and not exists (
      select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
      where (n.nspname = 'crm' and p.proname = 'marcar_potencial_lead_fn')
         or (n.nspname = 'private' and p.proname in ('potencial_rechazo', 'potencial_marcar_nucleo',
                                                     'potencial_evento_inmutable', 'potencial_bloquear_lead'))
    )
    and not exists (select 1 from crm.multiempresa_flags f where f.nombre = 'potencial_lead')
  ) is not true then
    raise exception 'PREFLIGHT potencial_lead: ya aplicada o aplicada a medias (hay objetos con estos nombres)';
  end if;

  if (
    pg_catalog.to_regprocedure('private.rol_crm(uuid)') is not null
    and pg_catalog.to_regprocedure('private.vendedor_ids_visibles(uuid)') is not null
    and pg_catalog.to_regprocedure('private.log_audit_crm()') is not null
    and pg_catalog.to_regprocedure('private.set_actualizado_en_crm()') is not null
    and pg_catalog.to_regprocedure('crm.bandera_activa(text)') is not null
  ) is not true then
    raise exception 'PREFLIGHT potencial_lead: falta un ayudante del que depende la migración';
  end if;

  -- La autorización de la puerta descansa en estos dos ayudantes: si cambiaron desde el
  -- ensayo en el banco, la migración se niega y hay que volver a revisarla. Huella de
  -- cuerpo + DEFINER + volatilidad + configuración + dueño: pg_get_functiondef no sirve aquí
  -- porque su texto cambia con el search_path de la sesión (medido en el banco el 30/09).
  select pg_catalog.md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|'
                        || coalesce(pg_catalog.array_to_string(p.proconfig, ','), '') || '|' || p.proowner::pg_catalog.regrole::text)
    into v_md5_rol
  from pg_catalog.pg_proc p where p.oid = 'private.rol_crm(uuid)'::pg_catalog.regprocedure;
  select pg_catalog.md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|'
                        || coalesce(pg_catalog.array_to_string(p.proconfig, ','), '') || '|' || p.proowner::pg_catalog.regrole::text)
    into v_md5_visibles
  from pg_catalog.pg_proc p where p.oid = 'private.vendedor_ids_visibles(uuid)'::pg_catalog.regprocedure;
  if (v_md5_rol = '16960a2a21cc5c372431c2dd67acafe4' and v_md5_visibles = '45ae492c03234b80336c0b8f5c8ac09b') is not true then
    raise exception 'PREFLIGHT potencial_lead: private.rol_crm (%) o private.vendedor_ids_visibles (%) no son los ensayados',
      v_md5_rol, v_md5_visibles;
  end if;
end;
$preflight$;

-- ── 1 · Tipo ───────────────────────────────────────────────────────────────────
create type crm.nivel_potencial as enum ('frio', 'tibio', 'estrella');
comment on type crm.nivel_potencial is
'Potencial comercial de un lead según su analista: frio (pinta mal, aún no se descarta), tibio (vale la pena seguirlo), estrella (máximo potencial). No es la etapa ni el descarte.';

-- ── 2 · Tablas ─────────────────────────────────────────────────────────────────
create table crm.lead_potencial (
  id uuid primary key default gen_random_uuid(),
  lead_id uuid not null references crm.leads(id),
  nivel crm.nivel_potencial not null,
  origen text not null,
  marcado_por uuid not null references public.perfiles(id),
  marcado_en timestamptz not null,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint lead_potencial_lead_unico unique (lead_id),
  constraint lead_potencial_origen_check check (origen in ('manual', 'caducidad')),
  constraint lead_potencial_fechas_finitas check (isfinite(marcado_en) and isfinite(creado_en) and isfinite(actualizado_en))
);
alter table crm.lead_potencial enable row level security;

create table crm.lead_potencial_eventos (
  id uuid primary key default gen_random_uuid(),
  orden bigint generated always as identity,
  lead_id uuid not null references crm.leads(id),
  nivel_anterior crm.nivel_potencial,
  nivel_nuevo crm.nivel_potencial not null,
  motivo text not null,
  por uuid references public.perfiles(id),
  creado_en timestamptz not null default now(),
  constraint lead_potencial_eventos_motivo_check check (motivo in ('manual', 'caducidad')),
  constraint lead_potencial_eventos_autor_check check ((motivo = 'manual') = (por is not null)),
  constraint lead_potencial_eventos_creado_en_finito check (isfinite(creado_en))
);
alter table crm.lead_potencial_eventos enable row level security;

create index lead_potencial_marcado_por_idx on crm.lead_potencial (marcado_por);
create index lead_potencial_nivel_idx on crm.lead_potencial (nivel, lead_id);
create index lead_potencial_eventos_lead_idx on crm.lead_potencial_eventos (lead_id, orden desc);
create index lead_potencial_eventos_por_idx on crm.lead_potencial_eventos (por) where por is not null;

comment on table crm.lead_potencial is
'Nivel VIGENTE de potencial de cada lead (una fila por lead). Solo se escribe por crm.marcar_potencial_lead_fn (y, desde la fase 2, por la caducidad diaria). Tabla propia para no disparar los ~20 disparadores de crm.leads ni reordenar la cartera. Sin grants para la API: se lee por puertas.';
comment on column crm.lead_potencial.id is 'Identificador de la fila.';
comment on column crm.lead_potencial.lead_id is 'Lead marcado. Único: la marca es del lead y viaja con él si se reasigna.';
comment on column crm.lead_potencial.nivel is 'Nivel vigente: frio, tibio o estrella.';
comment on column crm.lead_potencial.origen is 'Quién fijó el nivel vigente: manual (analista o supervisor) o caducidad (bajada automática por días sin gestión, fase 2).';
comment on column crm.lead_potencial.marcado_por is 'Perfil de la última persona que marcó el lead (no cambia con la caducidad).';
comment on column crm.lead_potencial.marcado_en is 'Última marca humana. Junto con la última gestión arranca el reloj de la caducidad.';
comment on column crm.lead_potencial.creado_en is 'Primera marca del lead.';
comment on column crm.lead_potencial.actualizado_en is 'Último cambio de la fila (marca o caducidad).';

comment on table crm.lead_potencial_eventos is
'Historial INMUTABLE de la marca de potencial: cada marca y cada bajada automática. Solo INSERT; UPDATE, DELETE y TRUNCATE se rechazan. No es una gestión: no vive en crm.actividades. Sin grants para la API.';
comment on column crm.lead_potencial_eventos.id is 'Identificador del evento.';
comment on column crm.lead_potencial_eventos.orden is 'Orden total de inserción. creado_en empata dentro de una misma transacción; el historial se ordena por esta columna.';
comment on column crm.lead_potencial_eventos.lead_id is 'Lead al que pertenece el evento.';
comment on column crm.lead_potencial_eventos.nivel_anterior is 'Nivel antes del cambio; null en la primera marca.';
comment on column crm.lead_potencial_eventos.nivel_nuevo is 'Nivel después del cambio (igual al anterior si se volvió a confirmar).';
comment on column crm.lead_potencial_eventos.motivo is 'manual (una persona marcó) o caducidad (bajó sola por días sin gestión).';
comment on column crm.lead_potencial_eventos.por is 'Perfil que marcó; null solo cuando el motivo es caducidad (lo hizo el sistema).';
comment on column crm.lead_potencial_eventos.creado_en is 'Momento del cambio.';

-- ── 3 · RLS: segundo candado de lectura (sin grants hoy) ──────────────────────
create policy lead_potencial_select on crm.lead_potencial
  for select to authenticated
  using (exists (select 1 from crm.leads l where l.id = lead_potencial.lead_id));
comment on policy lead_potencial_select on crm.lead_potencial is
'Segundo candado: si algún día se concede SELECT, ve la marca solo quien ve el lead (el exists corre con la RLS de crm.leads del que consulta).';

create policy lead_potencial_eventos_select on crm.lead_potencial_eventos
  for select to authenticated
  using (exists (select 1 from crm.leads l where l.id = lead_potencial_eventos.lead_id));
comment on policy lead_potencial_eventos_select on crm.lead_potencial_eventos is
'Segundo candado: si algún día se concede SELECT, ve el historial solo quien ve el lead (el exists corre con la RLS de crm.leads del que consulta).';

-- ── 4 · Disparadores: auditoría, updated_at e inmutabilidad del historial ──────
create function private.potencial_evento_inmutable()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  raise exception 'El historial de potencial no se modifica ni se borra' using errcode = 'P0409';
end;
$function$;
comment on function private.potencial_evento_inmutable() is
'Disparador que vuelve inmutable crm.lead_potencial_eventos (UPDATE, DELETE y TRUNCATE).';

create trigger trg_lead_potencial_touch before update on crm.lead_potencial
  for each row execute function private.set_actualizado_en_crm();
create trigger trg_audit_lead_potencial after insert or update or delete on crm.lead_potencial
  for each row execute function private.log_audit_crm();
create trigger lead_potencial_evento_inmutable before update or delete on crm.lead_potencial_eventos
  for each row execute function private.potencial_evento_inmutable();
create trigger lead_potencial_evento_no_truncate before truncate on crm.lead_potencial_eventos
  for each statement execute function private.potencial_evento_inmutable();
create trigger trg_audit_lead_potencial_eventos after insert or update or delete on crm.lead_potencial_eventos
  for each row execute function private.log_audit_crm();

-- ── 5 · Núcleo ─────────────────────────────────────────────────────────────────
create function private.potencial_bloquear_lead(p_lead_id uuid)
returns boolean
language plpgsql
volatile
security invoker
set search_path = ''
as $function$
begin
  -- Orden fijo: primero el candado consultivo del lead (serializa marcas y, en la fase 2, la
  -- caducidad), después la fila del lead en FOR SHARE (una reasignación, cierre o baja en
  -- vuelo termina antes, o espera a que la marca confirme). Ningún otro escritor de crm.leads
  -- toma este consultivo, así que no hay ciclo de espera.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.lead_potencial'), pg_catalog.hashtext(p_lead_id::text));
  perform 1 from crm.leads l where l.id = p_lead_id for share;
  -- Codex r2 R2-1: si no hubo fila que bloquear (inexistente o aún sin confirmar), la puerta
  -- rechaza: nunca autoriza sobre una fila que no quedó bloqueada.
  return found;
end;
$function$;
comment on function private.potencial_bloquear_lead(uuid) is
'Candado de la marca: consultivo por lead (hashtext(''crm.lead_potencial''), hashtext(lead_id)) + FOR SHARE de la fila del lead, hasta el final de la transacción. Devuelve si encontró y bloqueó la fila; sin fila la puerta rechaza. La caducidad (fase 2) debe tomar el mismo consultivo. Sin EXECUTE para la API.';

create function private.potencial_rechazo(p_actor uuid, p_lead_id uuid)
returns text
language plpgsql
stable
security invoker
set search_path = ''
as $function$
declare
  v_rol text;
  v_vendedor uuid;
  v_supervisor uuid;
  v_etapa text;
  v_activo boolean;
begin
  v_rol := private.rol_crm(p_actor);
  if (v_rol = 'vendedor' or v_rol = 'supervisor') is not true then
    return 'rol';
  end if;

  select l.vendedor_id, l.asignado_supervisor_id, l.etapa, l.activo
    into v_vendedor, v_supervisor, v_etapa, v_activo
  from crm.leads l
  where l.id = p_lead_id;
  if not found or v_activo is not true then
    return 'ambito';
  end if;

  -- Mismo ámbito que las ramas no-gerencia de leads_update: el dueño (vendedor_ids_visibles
  -- devuelve al analista él mismo y al supervisor su subárbol); y si está parqueado
  -- (vendedor_id null), SOLO un supervisor cuyo subárbol contiene la bandeja.
  if (case
        when v_vendedor is not null then v_vendedor in (select private.vendedor_ids_visibles(p_actor))
        else v_rol = 'supervisor' and v_supervisor in (select private.vendedor_ids_visibles(p_actor))
      end) is not true then
    return 'ambito';
  end if;

  if v_etapa is null or v_etapa in ('convertido', 'descartado') then
    return 'cerrado';
  end if;
  return 'ok';
end;
$function$;
comment on function private.potencial_rechazo(uuid, uuid) is
'Decide si el actor puede marcar el potencial del lead: ok = puede; rol | ambito | cerrado = motivo del rechazo (cualquier otro valor, NULL incluido, se rechaza). Solo vendedor (su lead) o supervisor (su subárbol y su parqueo). Se llama DESPUÉS de private.potencial_bloquear_lead. Sin EXECUTE para la API.';

create function private.potencial_marcar_nucleo(p_actor uuid, p_lead_id uuid, p_nivel crm.nivel_potencial)
returns crm.lead_potencial
language plpgsql
volatile
security invoker
set search_path = ''
as $function$
declare
  v_actual crm.lead_potencial;
  v_fila crm.lead_potencial;
  v_ahora timestamptz;
begin
  -- Reentrante: la puerta ya lo tomó; el núcleo no depende de ello.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.lead_potencial'), pg_catalog.hashtext(p_lead_id::text));
  -- Hora REAL, tomada una sola vez y después del candado (Codex r2 R2-4): now() es la hora de
  -- inicio de la transacción y dejaba el antirrebote y marcado_en desordenados entre marcas.
  v_ahora := pg_catalog.clock_timestamp();

  select p.* into v_actual from crm.lead_potencial p where p.lead_id = p_lead_id;

  -- Doble clic: misma persona, mismo nivel, marca manual de hace menos de 60 s → no escribe.
  if v_actual.id is not null and v_actual.nivel = p_nivel and v_actual.origen = 'manual'
     and v_actual.marcado_por = p_actor and v_actual.marcado_en > v_ahora - interval '60 seconds' then
    return v_actual;
  end if;

  insert into crm.lead_potencial as p (lead_id, nivel, origen, marcado_por, marcado_en)
  values (p_lead_id, p_nivel, 'manual', p_actor, v_ahora)
  on conflict (lead_id) do update
    set nivel = excluded.nivel,
        origen = 'manual',
        marcado_por = excluded.marcado_por,
        marcado_en = excluded.marcado_en
  returning p.* into v_fila;

  insert into crm.lead_potencial_eventos (lead_id, nivel_anterior, nivel_nuevo, motivo, por, creado_en)
  values (p_lead_id, v_actual.nivel, p_nivel, 'manual', p_actor, v_ahora);

  return v_fila;
end;
$function$;
comment on function private.potencial_marcar_nucleo(uuid, uuid, crm.nivel_potencial) is
'Operación atómica de marcar: fija el nivel vigente (origen manual, reinicia marcado_en) y deja su evento inmutable; el doble clic (misma persona y nivel en 60 s) no escribe. No autoriza: eso lo hace la puerta. Sin EXECUTE para la API.';

-- ── 6 · Puerta ─────────────────────────────────────────────────────────────────
create function crm.marcar_potencial_lead_fn(p_lead_id uuid, p_nivel crm.nivel_potencial)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_rechazo text;
  v_fila crm.lead_potencial;
begin
  if v_actor is null then
    raise exception 'Sesión requerida' using errcode = '42501';
  end if;
  if p_lead_id is null or p_nivel is null then
    raise exception 'Indica el lead y el nivel de potencial' using errcode = '22023';
  end if;
  -- Rol antes de tomar candados: gerencia y otros roles no bloquean nada ni sondean leads.
  if (private.rol_crm(v_actor) in ('vendedor', 'supervisor')) is not true then
    raise exception 'Solo el analista del lead o su supervisor pueden marcar su potencial' using errcode = '42501';
  end if;

  -- Candados y DESPUÉS la autorización decisiva (Codex r1 F1: sin esto, una reasignación o un
  -- cierre confirmado entre la comprobación y la escritura dejaba marcar con permiso caducado).
  if private.potencial_bloquear_lead(p_lead_id) is not true then
    raise exception 'Lead no encontrado o fuera de tu ámbito' using errcode = 'P0002';
  end if;
  v_rechazo := private.potencial_rechazo(v_actor, p_lead_id);
  if v_rechazo = 'rol' then
    raise exception 'Solo el analista del lead o su supervisor pueden marcar su potencial' using errcode = '42501';
  elsif v_rechazo = 'ambito' then
    raise exception 'Lead no encontrado o fuera de tu ámbito' using errcode = 'P0002';
  elsif v_rechazo = 'cerrado' then
    raise exception 'Un lead convertido o descartado no lleva marca de potencial' using errcode = '22023';
  elsif v_rechazo is distinct from 'ok' then
    raise exception 'Marca de potencial rechazada' using errcode = '42501';
  end if;

  if crm.bandera_activa('potencial_lead') is not true then
    raise exception 'La marca de potencial todavía no está activada' using errcode = '55000';
  end if;

  v_fila := private.potencial_marcar_nucleo(v_actor, p_lead_id, p_nivel);
  return pg_catalog.jsonb_build_object(
    'lead_id', v_fila.lead_id,
    'nivel', v_fila.nivel,
    'origen', v_fila.origen,
    'marcado_por', v_fila.marcado_por,
    'marcado_en', v_fila.marcado_en
  );
end;
$function$;
comment on function crm.marcar_potencial_lead_fn(uuid, crm.nivel_potencial) is
'Puerta: marca el potencial (frio, tibio, estrella) de un lead. Solo el analista dueño o su supervisor; gerencia y demás roles 42501; lead ajeno P0002; cerrado 22023; bandera potencial_lead apagada 55000. Autoriza tras bloquear el lead. Devuelve {lead_id, nivel, origen, marcado_por, marcado_en}.';

-- ── 7 · Bandera (apagada hasta la fase 3) ──────────────────────────────────────
insert into crm.multiempresa_flags (nombre, activo, descripcion)
values ('potencial_lead', false, 'Marca de potencial del lead (Frío, Tibio, Estrella): la puerta crm.marcar_potencial_lead_fn solo escribe con la bandera encendida')
on conflict (nombre) do nothing;

-- ── 8 · Dueños y permisos ──────────────────────────────────────────────────────
alter type crm.nivel_potencial owner to postgres;
alter table crm.lead_potencial owner to postgres;
alter table crm.lead_potencial_eventos owner to postgres;
alter function private.potencial_evento_inmutable() owner to postgres;
alter function private.potencial_bloquear_lead(uuid) owner to postgres;
alter function private.potencial_rechazo(uuid, uuid) owner to postgres;
alter function private.potencial_marcar_nucleo(uuid, uuid, crm.nivel_potencial) owner to postgres;
alter function crm.marcar_potencial_lead_fn(uuid, crm.nivel_potencial) owner to postgres;

revoke all on crm.lead_potencial, crm.lead_potencial_eventos from public, anon, authenticated, service_role;
revoke all on sequence crm.lead_potencial_eventos_orden_seq from public, anon, authenticated, service_role;

revoke all on function private.potencial_evento_inmutable() from public, anon, authenticated, service_role;
revoke all on function private.potencial_bloquear_lead(uuid) from public, anon, authenticated, service_role;
revoke all on function private.potencial_rechazo(uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function private.potencial_marcar_nucleo(uuid, uuid, crm.nivel_potencial) from public, anon, authenticated, service_role;
revoke all on function crm.marcar_potencial_lead_fn(uuid, crm.nivel_potencial) from public, anon, authenticated, service_role;
grant execute on function crm.marcar_potencial_lead_fn(uuid, crm.nivel_potencial) to authenticated;

-- ── 9 · Postflight ─────────────────────────────────────────────────────────────
do $postflight$
declare
  v_puerta pg_catalog.regprocedure := 'crm.marcar_potencial_lead_fn(uuid,crm.nivel_potencial)'::pg_catalog.regprocedure;
  v_privadas pg_catalog.regprocedure[] := array[
    'private.potencial_evento_inmutable()'::pg_catalog.regprocedure,
    'private.potencial_bloquear_lead(uuid)'::pg_catalog.regprocedure,
    'private.potencial_rechazo(uuid,uuid)'::pg_catalog.regprocedure,
    'private.potencial_marcar_nucleo(uuid,uuid,crm.nivel_potencial)'::pg_catalog.regprocedure
  ];
  v_objetos pg_catalog.regclass[] := array[
    'crm.lead_potencial'::pg_catalog.regclass,
    'crm.lead_potencial_eventos'::pg_catalog.regclass,
    'crm.lead_potencial_eventos_orden_seq'::pg_catalog.regclass
  ];
  v_disparadores text;
  v_policies text;
begin
  -- Texto de catálogo independiente de la sesión: todo calificado (Codex r1 F5).
  perform pg_catalog.set_config('search_path', '', true);

  -- Puerta: DEFINER, dueño postgres, search_path vacío, lock_timeout, EXECUTE solo authenticated.
  if (
    exists (
      select 1 from pg_catalog.pg_proc p
      where p.oid = v_puerta and p.prosecdef and p.proowner = 'postgres'::pg_catalog.regrole
        and p.provolatile = 'v'
        and p.proconfig is not null
        and p.proconfig @> array['search_path=""', 'lock_timeout=5s']::text[]
        and p.proacl is not null
    )
    and not exists (select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
                    where p.oid = v_puerta
                      and a.grantee not in ('postgres'::pg_catalog.regrole, 'authenticated'::pg_catalog.regrole))
    and exists (select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
                where p.oid = v_puerta and a.privilege_type = 'EXECUTE' and a.grantee = 'authenticated'::pg_catalog.regrole)
  ) is not true then
    raise exception 'POSTFLIGHT potencial_lead: la puerta no quedó DEFINER/postgres/search_path vacío/EXECUTE solo authenticated';
  end if;

  -- Privadas: INVOKER, dueño postgres, search_path vacío y ACL explícita solo de postgres.
  if (
    (select count(*) from pg_catalog.pg_proc p
      where p.oid = any (v_privadas) and not p.prosecdef and p.proowner = 'postgres'::pg_catalog.regrole
        and p.proconfig is not null and p.proconfig @> array['search_path=""']::text[]
        and p.proacl is not null) = 4
    and not exists (select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
                    where p.oid = any (v_privadas) and a.grantee <> 'postgres'::pg_catalog.regrole)
  ) is not true then
    raise exception 'POSTFLIGHT potencial_lead: los ayudantes privados no quedaron INVOKER/search_path vacío/sin EXECUTE para la API';
  end if;

  -- Tablas y secuencia: dueño postgres y ACL en LISTA BLANCA (solo postgres), RLS activa en
  -- las dos tablas; tipo con dueño postgres. Permisos EFECTIVOS de la API en cero (herencia
  -- incluida).
  if (
    (select count(*) from pg_catalog.pg_class c
      where c.oid = any (v_objetos) and c.relowner = 'postgres'::pg_catalog.regrole and c.relacl is not null) = 3
    and not exists (select 1 from pg_catalog.pg_class c, pg_catalog.aclexplode(c.relacl) a
                    where c.oid = any (v_objetos) and a.grantee <> 'postgres'::pg_catalog.regrole)
    and (select count(*) from pg_catalog.pg_class c
          where c.oid in ('crm.lead_potencial'::pg_catalog.regclass, 'crm.lead_potencial_eventos'::pg_catalog.regclass)
            and c.relrowsecurity) = 2
    and (select t.typowner from pg_catalog.pg_type t where t.oid = 'crm.nivel_potencial'::pg_catalog.regtype) = 'postgres'::pg_catalog.regrole
    and not exists (
      select 1
      from unnest(array['anon', 'authenticated', 'service_role']) r(rol),
           unnest(array['crm.lead_potencial', 'crm.lead_potencial_eventos']) t(tabla),
           unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE']) x(priv)
      where pg_catalog.has_table_privilege(r.rol, t.tabla, x.priv)
    )
  ) is not true then
    raise exception 'POSTFLIGHT potencial_lead: dueño, ACL, RLS o permisos efectivos de tablas, secuencia o tipo no son los previstos';
  end if;

  -- Policies exactas: una SELECT por tabla, para authenticated, con su exists (Codex r1 F5).
  select string_agg(pp.tablename || '|' || pp.cmd || '|' || pp.roles::text || '|'
                    || pg_catalog.regexp_replace(coalesce(pp.qual, ''), '\s+', ' ', 'g') || '|' || coalesce(pp.with_check, ''),
                    ' ## ' order by pp.tablename)
    into v_policies
  from pg_catalog.pg_policies pp
  where pp.schemaname = 'crm' and pp.tablename in ('lead_potencial', 'lead_potencial_eventos');
  if (v_policies = 'lead_potencial|SELECT|{authenticated}|(EXISTS ( SELECT 1 FROM crm.leads l WHERE (l.id = lead_potencial.lead_id)))|'
                 || ' ## lead_potencial_eventos|SELECT|{authenticated}|(EXISTS ( SELECT 1 FROM crm.leads l WHERE (l.id = lead_potencial_eventos.lead_id)))|') is not true then
    raise exception 'POSTFLIGHT potencial_lead: policies inesperadas: %', coalesce(v_policies, '(ninguna)');
  end if;

  -- Disparadores exactos (momento, eventos, nivel y función) y activos para sesiones normales.
  select string_agg(pg_catalog.pg_get_triggerdef(t.oid) || ' [' || t.tgenabled::text || ']', ' ## ' order by t.tgname)
    into v_disparadores
  from pg_catalog.pg_trigger t
  where t.tgrelid in ('crm.lead_potencial'::pg_catalog.regclass, 'crm.lead_potencial_eventos'::pg_catalog.regclass)
    and not t.tgisinternal;
  if (v_disparadores =
        'CREATE TRIGGER lead_potencial_evento_inmutable BEFORE DELETE OR UPDATE ON crm.lead_potencial_eventos FOR EACH ROW EXECUTE FUNCTION private.potencial_evento_inmutable() [O]'
     || ' ## CREATE TRIGGER lead_potencial_evento_no_truncate BEFORE TRUNCATE ON crm.lead_potencial_eventos FOR EACH STATEMENT EXECUTE FUNCTION private.potencial_evento_inmutable() [O]'
     || ' ## CREATE TRIGGER trg_audit_lead_potencial AFTER INSERT OR DELETE OR UPDATE ON crm.lead_potencial FOR EACH ROW EXECUTE FUNCTION private.log_audit_crm() [O]'
     || ' ## CREATE TRIGGER trg_audit_lead_potencial_eventos AFTER INSERT OR DELETE OR UPDATE ON crm.lead_potencial_eventos FOR EACH ROW EXECUTE FUNCTION private.log_audit_crm() [O]'
     || ' ## CREATE TRIGGER trg_lead_potencial_touch BEFORE UPDATE ON crm.lead_potencial FOR EACH ROW EXECUTE FUNCTION private.set_actualizado_en_crm() [O]'
  ) is not true then
    raise exception 'POSTFLIGHT potencial_lead: disparadores inesperados: %', coalesce(v_disparadores, '(ninguno)');
  end if;

  -- Bandera creada y apagada.
  if (select f.activo from crm.multiempresa_flags f where f.nombre = 'potencial_lead') is distinct from false then
    raise exception 'POSTFLIGHT potencial_lead: la bandera potencial_lead no quedó creada y apagada';
  end if;

  raise notice 'potencial_lead OK: tipo, 2 tablas (RLS, sin grants API), núcleo INVOKER con candado, puerta DEFINER solo authenticated, bandera apagada.';
end;
$postflight$;

commit;

```
