ROLE: SECONDARY_REVIEWER.
Do not modify files. Do not implement the task. Do not invoke Claude. Do not delegate to another coding agent. Do not create another review chain.

# Encargo de revisión — RONDA 2 (LEVEL 3) · Potencial del lead, FASE 2 (caducidad)

Eres el revisor secundario. Sin base de datos ni red: todo está transcrito abajo. Responde con VERDICT (APPROVE / CHANGES_REQUESTED), SUMMARY, FINDINGS P0–P3 con evidencia, riesgos y test gaps, NEXT ACTIONS y CONFIDENCE. Tu tarea: REFUTAR los arreglos de esta ronda. El contexto de la fase 1 no cambió desde tu ronda 1.

## Qué cambió desde tu ronda 1 (y el auditor-rls, que dio PASS con 7 P3)
- **F1 (elegibilidad no revalidada):** rediseño «NUNCA ESPERA»: por candidato `pg_try_advisory_xact_lock` (mismo consultivo de la fase 1) y `select activo, etapa from crm.leads ... for share skip locked`; si alguno está ocupado, el lead se salta hasta la próxima corrida. Bajo los candados se revalida el lead (activo, etapa no null ni cerrada) y se relee la marca. Así la tarea no forma ciclos de espera ni frena a los usuarios (el auditor desaconsejaba FOR SHARE con espera durante todo el job). `set lock_timeout = '10s'` en la función como red. Guardas `continue when (...) is not true`; solo baja: `continue when (v_nuevo < v_actual.nivel) is not true` (enum frio < tibio < estrella).
- **F2 (domingo):** el job corre TODOS los días (`10 10 * * *`); el domingo sigue sin contar como día. Lo cumplido el sábado se aplica el domingo de madrugada.
- **F3 (reversa sin pg_cron):** todo lo que nombra `cron.job` va en IF anidados. Ciclo completo probado SIN la extensión.
- **F4 (contacto futuro):** `potencial_reloj(lead, marcado_en, p_hasta)` solo cuenta contactos con `creado_en < p_hasta`; la tarea pasa el inicio de «hoy» en Lima. Un contacto de 2099 no cuenta hasta su hora (no se recorta el reloj a «ahora»). Además el auditor confirmó que las inserciones manuales de actividades llevan sello del servidor. `crm.actividades.creado_en` es timestamptz (verificado en el volcado).
- **F5 (contexto del job):** preflight exige `current_user = postgres`, `postgres` con BYPASSRLS, `cron.timezone` GMT/UTC y que no exista ya un job con ese nombre (medido en producción, solo lectura: current_user=postgres, cron.timezone=GMT, todos los jobs postgres@postgres, postgres BYPASSRLS). Postflight: UN solo job con ese nombre, con horario, comando, `username = 'postgres'`, `database = current_database()` y activo.
- Lote y fallos: la tarea ya no espera candados; un error real (no de contención) aborta la corrida del día y queda en `cron.job_run_details` (se reintenta al día siguiente; la regla es acumulativa). `verificar-caducidad.sql` mostrará la última corrida.
- Supuestos de negocio que el auditor pidió escribir (a confirmar con el dueño antes de encender la bandera): Estrella llega a Frío a los 10 días en total; el tiempo cerrado/inactivo cuenta como sin gestión; agendar o reasignar no reinicia el reloj. Riesgo residual escrito: un contacto confirmado entre la relectura y el UPDATE no se ve.

## Evidencia (banco Docker propio con el esquema de prod y pg_cron)
- SIN pg_cron: migración PASS (aviso) → reversa PASS → migración PASS → reversa PASS.
- CON pg_cron: migración PASS (job `10 10 * * *` postgres@postgres activo) → repetida se niega → reversa de fase 1 con la 2 puesta se niega → reversa f2 PASS (sin job) → repetida se niega → migración PASS.
- prueba-caducidad.sql (abajo, la tarea llamada COMO postgres): 46/46. Fase 1 sin regresión 75/75.
- prueba-concurrencia-caducidad.sh (abajo): 10/10 (re-marca en vuelo: salta sin esperar; descarte en vuelo: salta sin esperar y la marca queda intacta; la corrida siguiente baja lo vencido). Mutantes: con espera del consultivo → «NO esperó» falla; sin SKIP LOCKED → «NO esperó» falla.
- Mutantes de lógica cazados: domingo cuenta (6 fallas), hoy incluido (9), nota es gestión (5), reloj sin contacto (7), contacto futuro cuenta (4), sin zona Lima (3: contacto viernes 21:00 Lima), umbral 4 (4), tibio a los 5 (11); cerrados en filtro Y relectura (3). «Cerrados» solo en el filtro sobrevive: la relectura bajo candado lo cubre (doble candado).
- Mutantes de la migración rechazados: EXECUTE abierto, horario `1-6`, sin lock_timeout, regla distinta.

## Preguntas
1. ¿`pg_try_advisory_xact_lock` + `FOR SHARE SKIP LOCKED` cierra F1 sin abrir otro hueco (p. ej. el lead se salta para siempre si siempre está ocupado a las 05:10)?
2. ¿El preflight del contexto del job (current_user, BYPASSRLS, cron.timezone) puede dar falso rojo o falso verde en producción?
3. ¿`continue when (v_nuevo < v_actual.nivel) is not true` es correcto con el orden del enum?
4. ¿Algo más que bloquee publicar esta fase con la bandera de la fase 1 todavía apagada?

## Archivos

### supabase/migrations/20260930235917_crm_potencial_lead_caducidad.sql
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
--   · private.potencial_reloj(lead, marcado_en, hasta): lo más reciente entre la última marca
--     humana y el último CONTACTO del lead ANTERIOR a «hasta» (los 5 tipos del índice
--     actividades_contacto_episodio_idx: llamada realizada o no contestada, WhatsApp enviado o
--     recibido, reunión realizada). Las notas no cuentan: el sistema también escribe notas (p. ej.
--     al anular un cierre). Un contacto con fecha futura no congela el reloj (Codex f2 r1 F4): no
--     cuenta hasta que llega su hora.
--   · private.potencial_nivel_tras(nivel, días): la regla en UN solo lugar (≥10 → frío; ≥5 y
--     estrella → tibio; si no, igual). La usan el filtro de candidatos y el bucle (y la pantalla de
--     la fase 3 podrá usarla para «baja en N días»).
--   · private.potencial_caducar(p_hoy): recorre las marcas Estrella y Tibio de leads activos y
--     abiertos. NUNCA ESPERA (Codex f2 r1 F1, auditor P3-1/P3-2): por cada candidato intenta el
--     MISMO candado consultivo de la puerta de la fase 1 y la fila del lead en FOR SHARE SKIP LOCKED;
--     si alguno está ocupado, lo deja para la próxima corrida. Bajo los candados relee el lead
--     (activo y abierto) y la marca, recalcula y solo BAJA (origen 'caducidad'; marcado_por y
--     marcado_en intactos; evento inmutable con autor nulo). Idempotente: un día saltado se pone
--     al día al siguiente (la regla es acumulativa).
--   · pg_cron 'crm-potencial-lead-caducidad' a las 10:10 UTC (05:10 Lima) TODOS los días (Codex
--     f2 r1 F2): el domingo no cuenta como día, pero lo que se cumplió el sábado se aplica el
--     domingo de madrugada. Sin pg_cron (banco): aviso y no se programa.
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
    and pg_catalog.to_regprocedure('private.potencial_caducar(date)') is null
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
create function private.potencial_reloj(p_lead_id uuid, p_marcado_en timestamptz, p_hasta timestamptz)
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
      and a.creado_en < p_hasta), p_marcado_en));
$function$;
comment on function private.potencial_reloj(uuid, timestamptz, timestamptz) is
'Desde cuándo corre el reloj de la caducidad del potencial: lo más reciente entre la última marca humana y el último CONTACTO del lead anterior a p_hasta (llamada realizada o no contestada, WhatsApp enviado o recibido, reunión realizada). Las notas no cuentan; un contacto con fecha futura no cuenta hasta su hora.';

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
set lock_timeout = '10s'
as $function$
declare
  v_lead uuid;
  v_hasta timestamptz;
  v_activo boolean;
  v_etapa text;
  v_actual crm.lead_potencial;
  v_nuevo crm.nivel_potencial;
  v_n integer := 0;
begin
  if p_hoy is null then
    raise exception 'Fecha de referencia requerida' using errcode = '22023';
  end if;
  -- Contactos que cuentan: los anteriores al inicio de «hoy» en Lima.
  v_hasta := p_hoy::timestamp at time zone 'America/Lima';

  -- Candidatos SIN candado (barato).
  for v_lead in
    select p.lead_id
    from crm.lead_potencial p
    join crm.leads l on l.id = p.lead_id
    where p.nivel in ('estrella', 'tibio')
      and l.activo is true
      and l.etapa not in ('convertido', 'descartado')
      and private.potencial_nivel_tras(p.nivel, private.dias_lunes_a_sabado(
            (private.potencial_reloj(p.lead_id, p.marcado_en, v_hasta) at time zone 'America/Lima')::date, p_hoy)) < p.nivel
    order by p.lead_id
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
      (private.potencial_reloj(v_lead, v_actual.marcado_en, v_hasta) at time zone 'America/Lima')::date, p_hoy));
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
comment on function private.potencial_caducar(date) is
'Caducidad diaria del potencial del lead: Estrella → Tibio con 5 días completos (lunes a sábado) sin contacto ni marca; Tibio → Frío con 10. Solo leads activos y abiertos. Nunca espera: intenta el candado consultivo de la marca y la fila del lead (SKIP LOCKED); si están ocupados, deja el lead para la próxima corrida. Relee bajo los candados, solo baja y deja evento inmutable (motivo caducidad, autor nulo). Devuelve cuántas marcas bajó. Idempotente. Lo invoca pg_cron (crm-potencial-lead-caducidad) como postgres. Sin EXECUTE para la API.';

-- ── 4 · Dueños y permisos ─────────────────────────────────────────────────────
alter function private.dias_lunes_a_sabado(date, date) owner to postgres;
alter function private.potencial_reloj(uuid, timestamptz, timestamptz) owner to postgres;
alter function private.potencial_nivel_tras(crm.nivel_potencial, integer) owner to postgres;
alter function private.potencial_caducar(date) owner to postgres;
revoke all on function private.dias_lunes_a_sabado(date, date) from public, anon, authenticated, service_role;
revoke all on function private.potencial_reloj(uuid, timestamptz, timestamptz) from public, anon, authenticated, service_role;
revoke all on function private.potencial_nivel_tras(crm.nivel_potencial, integer) from public, anon, authenticated, service_role;
revoke all on function private.potencial_caducar(date) from public, anon, authenticated, service_role;

-- ── 5 · Programación diaria (05:10 Lima, todos los días) ──────────────────────
do $cron$
begin
  if pg_catalog.to_regprocedure('cron.schedule(text,text,text)') is null then
    raise notice 'pg_cron no está disponible: no se programa la caducidad del potencial.';
    return;
  end if;
  perform cron.schedule(
    'crm-potencial-lead-caducidad',
    '10 10 * * *',  -- 10:10 GMT = 05:10 Lima, antes de que empiece la jornada
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
    and exists (select 1 from pg_catalog.pg_proc p
                where p.oid = 'private.potencial_caducar(date)'::pg_catalog.regprocedure
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
            where j.jobname = 'crm-potencial-lead-caducidad' and j.schedule = '10 10 * * *'
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

```

### supabase/scripts/potencial-lead/reversa-caducidad.sql
```sql
-- REVERSA de 20260930235917_crm_potencial_lead_caducidad (fase 2).
-- Desprograma el job (si existe) y quita las cuatro funciones. Los eventos con motivo 'caducidad'
-- ya escritos SE QUEDAN: son historial inmutable, y los niveles bajados no se «suben» solos (una
-- persona vuelve a marcar si quiere). Conserva la fila de schema_migrations: anotarlo en
-- MIGRACIONES.md. Debe correr ANTES que la reversa de la fase 1.
-- Codex f2 r1 F3: todo lo que nombra cron.job va en un IF propio (plpgsql prepara cada expresión al
-- llegar a ella), para que funcione también en una base sin pg_cron.
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
  if pg_catalog.to_regclass('cron.job') is not null and pg_catalog.to_regprocedure('cron.unschedule(text)') is not null then
    if exists (select 1 from cron.job where jobname = 'crm-potencial-lead-caducidad') then
      perform cron.unschedule('crm-potencial-lead-caducidad');
    end if;
  end if;
end;
$chk$;

drop function private.potencial_caducar(date);
drop function private.potencial_nivel_tras(crm.nivel_potencial, integer);
drop function private.potencial_reloj(uuid, timestamptz, timestamptz);
drop function private.dias_lunes_a_sabado(date, date);

do $post$
begin
  if (
    pg_catalog.to_regprocedure('private.potencial_caducar(date)') is null
    and pg_catalog.to_regprocedure('private.potencial_nivel_tras(crm.nivel_potencial,integer)') is null
    and pg_catalog.to_regprocedure('private.potencial_reloj(uuid,timestamp with time zone,timestamp with time zone)') is null
    and pg_catalog.to_regprocedure('private.dias_lunes_a_sabado(date,date)') is null
  ) is not true then
    raise exception 'REVERSA potencial_caducidad: quedaron funciones';
  end if;
  if pg_catalog.to_regclass('cron.job') is not null then
    if exists (select 1 from cron.job where jobname = 'crm-potencial-lead-caducidad') then
      raise exception 'REVERSA potencial_caducidad: quedó el job';
    end if;
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
-- sáb 10-10, dom 10-11, lun 10-12, vie 10-16, sáb 10-17, lun 10-19. Los domingos no cuentan como
-- día, pero la tarea corre a diario. La tarea se llama COMO postgres (así corre en pg_cron).
begin;
set local lock_timeout = '5s';

create temp table act (k text primary key, id uuid not null default gen_random_uuid()) on commit drop;
insert into act (k) values ('S1'), ('V1');
create temp table lds (k text primary key, id uuid not null default gen_random_uuid()) on commit drop;
insert into lds (k) values ('A'), ('B'), ('C'), ('D'), ('E'), ('F'), ('G'), ('H'), ('I'), ('J'), ('K'), ('L');
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
-- La tarea, como la corre pg_cron: con el rol postgres (BYPASSRLS), no como supabase_admin.
create function pg_temp.caducar(p_hoy date) returns integer language plpgsql as $f$
declare v integer;
begin
  set local role postgres;
  v := private.potencial_caducar(p_hoy);
  reset role;
  return v;
end $f$;

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
  (pg_temp.l('J'), 'whatsapp_enviado', 'prueba de caducidad', pg_temp.a('V1'), pg_temp.lima('2026-10-09 18:00')),
  -- K: contacto el viernes 10-09 a las 21:00 Lima (en UTC ya es sábado 10-10): prueba la zona.
  (pg_temp.l('K'), 'llamada_realizada', 'prueba de caducidad', pg_temp.a('V1'), pg_temp.lima('2026-10-09 21:00')),
  -- L: un contacto con fecha FUTURA no congela el reloj.
  (pg_temp.l('L'), 'reunion_realizada', 'prueba de caducidad', pg_temp.a('V1'), pg_temp.lima('2099-01-01 10:00'));
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
    select to_char(private.potencial_reloj(p.lead_id, p.marcado_en, pg_temp.lima('2026-10-12 00:00')) at time zone 'America/Lima', 'YYYY-MM-DD HH24:MI')
    from crm.lead_potencial p where p.lead_id = pg_temp.l('J')));
  perform pg_temp.esperar('reloj de C: la nota NO lo mueve', '2026-10-05 10:00', (
    select to_char(private.potencial_reloj(p.lead_id, p.marcado_en, pg_temp.lima('2026-10-12 00:00')) at time zone 'America/Lima', 'YYYY-MM-DD HH24:MI')
    from crm.lead_potencial p where p.lead_id = pg_temp.l('C')));
  perform pg_temp.esperar('reloj de L: el contacto de 2099 aún no cuenta', '2026-10-05 10:00', (
    select to_char(private.potencial_reloj(p.lead_id, p.marcado_en, pg_temp.lima('2026-10-12 00:00')) at time zone 'America/Lima', 'YYYY-MM-DD HH24:MI')
    from crm.lead_potencial p where p.lead_id = pg_temp.l('L')));
  perform pg_temp.esperar('dom 10-11: 5 días completos ya (mar-sáb)', '5', private.dias_lunes_a_sabado('2026-10-05', '2026-10-11')::text);
  perform pg_temp.esperar('hasta antes que desde = 0', '0', private.dias_lunes_a_sabado('2026-10-12', '2026-10-05')::text);
  begin
    perform private.potencial_caducar(null);
    perform pg_temp.esperar('fecha nula', '22023', 'ok');
  exception when others then
    perform pg_temp.esperar('fecha nula', '22023', sqlstate);
  end;

  -- ── Sábado 10-10: 4 días completos (mar-vie) → nadie baja ──
  v_n := pg_temp.caducar('2026-10-10');
  perform pg_temp.esperar('sáb 10-10: no baja nadie', '0', v_n::text);
  perform pg_temp.esperar('A sigue estrella el sábado', 'estrella/manual', pg_temp.nivel('A'));

  -- ── Domingo 10-11: ya hay 5 días completos (mar-sáb): baja el domingo de madrugada ──
  v_n := pg_temp.caducar('2026-10-11');
  perform pg_temp.esperar('dom 10-11: bajan A, C, D, I y L (B, J y K tuvieron contacto; E es tibio)', '5', v_n::text);
  perform pg_temp.esperar('L: el contacto de 2099 no la congeló', 'tibio/caducidad', pg_temp.nivel('L'));
  -- ── Lunes 10-12: nada nuevo (ya se aplicó el domingo) ──
  v_n := pg_temp.caducar('2026-10-12');
  perform pg_temp.esperar('lun 10-12: 0 (lo del sábado ya se aplicó el domingo)', '0', v_n::text);
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
  v_n := pg_temp.caducar('2026-10-12');
  perform pg_temp.esperar('lun 10-12 otra vez: 0', '0', v_n::text);
  perform pg_temp.esperar('A: un solo evento', 'estrella>tibio:caducidad:sistema', pg_temp.historial('A'));

  -- ── I: el analista vuelve a marcar estrella el martes 10-13: el reloj arranca de nuevo ──
  update crm.lead_potencial set nivel = 'estrella', origen = 'manual', marcado_en = pg_temp.lima('2026-10-13 10:00')
   where lead_id = pg_temp.l('I');

  -- ── Viernes 10-16: B lleva 6 días desde su contacto (vie, sáb, lun-jue) ──
  v_n := pg_temp.caducar('2026-10-16');
  perform pg_temp.esperar('vie 10-16: bajan B, J y K', '3', v_n::text);
  perform pg_temp.esperar('K (llamada del viernes 21:00 Lima) baja el viernes 10-16: el día es de Lima, no de UTC', 'tibio/caducidad', pg_temp.nivel('K'));
  perform pg_temp.esperar('J (WhatsApp del viernes 10-09: 5 días) baja a tibio', 'estrella>tibio:caducidad:sistema', pg_temp.historial('J'));
  perform pg_temp.esperar('B baja a tibio', 'tibio/caducidad', pg_temp.nivel('B'));
  perform pg_temp.esperar('I re-marcado el martes sigue estrella', 'estrella/manual', pg_temp.nivel('I'));

  -- ── Sábado 10-17: 10 días desde el lunes 10-05 ──
  v_n := pg_temp.caducar('2026-10-17');
  perform pg_temp.esperar('sáb 10-17: bajan a frío A, C, D, E y L', '5', v_n::text);
  perform pg_temp.esperar('J sigue tibio el sábado (6 días desde su contacto; con el reloj de la marca serían 10)', 'tibio/caducidad', pg_temp.nivel('J'));
  perform pg_temp.esperar('A: tibio → frío', 'estrella>tibio:caducidad:sistema,tibio>frio:caducidad:sistema', pg_temp.historial('A'));
  perform pg_temp.esperar('D: estrella → tibio → frío', 'estrella>tibio:caducidad:sistema,tibio>frio:caducidad:sistema', pg_temp.historial('D'));
  perform pg_temp.esperar('E: tibio manual → frío', 'tibio>frio:caducidad:sistema', pg_temp.historial('E'));
  perform pg_temp.esperar('B (tibio desde el viernes, reloj del jueves 10-08) sigue tibio', 'tibio/caducidad', pg_temp.nivel('B'));
  perform pg_temp.esperar('I (re-marcado 10-13) sigue estrella', 'estrella/manual', pg_temp.nivel('I'));

  -- ── Un apagón de la tarea: estrella sin tocar 11 días baja DE GOLPE a frío, con un solo evento ──
  update crm.lead_potencial set nivel = 'estrella', origen = 'manual', marcado_en = pg_temp.lima('2026-10-05 10:00')
   where lead_id = pg_temp.l('F');
  v_n := pg_temp.caducar('2026-10-19');
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
# SOLO en el banco Docker propio. La tarea NUNCA espera (Codex f2 r1 F1, auditor P3-1/P3-2):
#   A · una re-marca del analista en vuelo (tiene el candado consultivo del lead): la tarea salta ese
#       lead al instante, no lo baja, y el lead queda para la próxima corrida.
#   B · un descarte en vuelo (fila del lead bloqueada): la tarea salta el lead al instante (SKIP
#       LOCKED) y, confirmado el descarte, la marca queda intacta.
#   C · la próxima corrida, ya sin nada en vuelo, baja lo que correspondía.
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

echo "A · la tarea se cruza con una re-marca en vuelo"
( psql_as postgres -c "begin; select pg_advisory_xact_lock(hashtext('crm.lead_potencial'), hashtext('$L1')); update crm.lead_potencial set marcado_en = '2026-10-12 09:00'::timestamp at time zone 'America/Lima', origen = 'manual' where lead_id = '$L1'; select pg_sleep(3); commit;" >/dev/null ) &
sleep 1
t0=$(date +%s%N); r=$(psql_as postgres -c "select private.potencial_caducar('2026-10-12')" 2>&1 | tail -1); t1=$(date +%s%N); wait
esperar "la tarea salta el lead ocupado (0 cambios)" '^0$' "$r"
esperar "la tarea NO esperó (< 1 s)" '^1$' "$(( (t1 - t0) < 1000000000 ? 1 : 0 ))"
esperar "el lead sigue estrella manual" '^estrella\|manual$' "$(psql_as postgres -c "select nivel || '|' || origen from crm.lead_potencial where lead_id = '$L1'")"
esperar "sin eventos de caducidad" '^0$' "$(psql_as postgres -c "select count(*) from crm.lead_potencial_eventos where lead_id = '$L1'")"

echo "B · la tarea se cruza con un descarte en vuelo"
psql_as postgres -c "update crm.lead_potencial set marcado_en = '2026-10-05 10:00'::timestamp at time zone 'America/Lima' where lead_id = '$L1'" >/dev/null
( psql_as supabase_admin -c "begin; set local session_replication_role = replica; update crm.leads set etapa = 'descartado', motivo_descarte = 'sin_interes' where id = '$L1'; select pg_sleep(3); commit;" >/dev/null ) &
sleep 1
t0=$(date +%s%N); r=$(psql_as postgres -c "select private.potencial_caducar('2026-10-12')" 2>&1 | tail -1); t1=$(date +%s%N); wait
esperar "la tarea salta el lead bloqueado (0 cambios)" '^0$' "$r"
esperar "la tarea NO esperó (< 1 s)" '^1$' "$(( (t1 - t0) < 1000000000 ? 1 : 0 ))"
esperar "confirmado el descarte, la marca quedó intacta" '^estrella\|manual$' "$(psql_as postgres -c "select nivel || '|' || origen from crm.lead_potencial where lead_id = '$L1'")"
esperar "y la tarea siguiente tampoco toca un lead descartado" '^0$' "$(psql_as postgres -c "select private.potencial_caducar('2026-10-12')")"

echo "C · sin nada en vuelo, la corrida siguiente baja lo que tocaba"
psql_as supabase_admin -c "set session_replication_role = replica; update crm.leads set etapa = 'contactado', motivo_descarte = null where id = '$L1';" >/dev/null
esperar "baja la estrella vencida" '^1$' "$(psql_as postgres -c "select private.potencial_caducar('2026-10-12')")"
esperar "queda tibio por caducidad" '^tibio\|caducidad$' "$(psql_as postgres -c "select nivel || '|' || origen from crm.lead_potencial where lead_id = '$L1'")"

limpiar
echo "CONCURRENCIA caducidad: $ok OK, $mal FALLAS"
[ "$mal" -eq 0 ]

```
