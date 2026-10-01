ROLE: SECONDARY_REVIEWER.
Do not modify files. Do not implement the task. Do not invoke Claude. Do not delegate to another coding agent. Do not create another review chain.

# Encargo de revisión — RONDA 2 (LEVEL 3) · Potencial del lead, fase 1

Eres el revisor secundario. Sin base de datos ni red: todo está transcrito abajo. Responde con VERDICT (APPROVE / CHANGES_REQUESTED), SUMMARY, FINDINGS P0–P3 con evidencia (archivo/línea/fragmento), riesgos y test gaps, NEXT ACTIONS y CONFIDENCE. Sin hallazgo sin evidencia. Tu tarea: REFUTAR los arreglos de esta ronda. El contexto vivo de producción (rol_crm, vendedor_ids_visibles, policies de crm.leads, leads_before_update, bandera_activa, log_audit_crm) no cambió respecto de tu ronda 1.

## Qué cambió desde tu ronda 1 (y el auditor-rls r1)
- **F1 (autorización obsoleta):** nuevo ayudante VOLATILE `private.potencial_bloquear_lead`: candado consultivo por lead + `perform 1 from crm.leads where id = … for share`. La puerta: sesión → args → rol (sin tomar candados) → `potencial_bloquear_lead` → `potencial_rechazo` (decisiva, DESPUÉS de los candados) → bandera → núcleo. En READ COMMITTED la sentencia de asignación que llama a `potencial_rechazo` toma instantánea nueva tras obtener el candado.
- **F2 (reversa):** `select … from crm.multiempresa_flags … for update` + `lock table crm.lead_potencial, crm.lead_potencial_eventos in access exclusive mode` ANTES de comprobar el vacío; sostenidos hasta el commit.
- **F3:** `idDe(clave)` y `marcarId(cliente, id)` separados; el UUID inexistente va por `marcarId`.
- **F4:** el bloque lee fuera de banda si la puerta existe y si la bandera está encendida; con la bandera encendida hace `fail` y NO llama a la puerta. Sin vía fuera de banda: salto ruidoso (FALLO con `CRM_RLS_EXIGE_POTENCIAL=1`).
- **F5:** el postflight fija `search_path` vacío (set_config local) y compara el texto EXACTO de las 2 policies (espacios normalizados, más `with_check` vacío) y de los 5 disparadores (`pg_get_triggerdef` + `tgenabled`).
- **b (NULL/parqueo/etapa):** `potencial_rechazo` devuelve `'ok'` explícito (la puerta rechaza todo lo que no sea `'ok'`, NULL incluido); la rama de parqueo exige `v_rol = 'supervisor'`; `etapa is null` se trata como cerrado.
- **d (identidad):** la huella de `rol_crm`/`vendedor_ids_visibles` incluye `proowner`. Tablas, secuencia y tipo con `owner to postgres`; postflight con LISTA BLANCA por `aclexplode(relacl)` (solo postgres) y permisos EFECTIVOS `has_table_privilege` de anon/authenticated/service_role en cero.
- **Auditor P2:** migración envuelta en `begin; set local lock_timeout = '5s'; … commit;`.
- **Auditor (arquitectura):** SIN grant SELECT a authenticated (regla de 4 capas: la pantalla leerá por una puerta en la fase 3). Las policies SELECT quedan como segundo candado.
- **Antirrebote:** el núcleo no escribe si la misma persona repite el mismo nivel dentro de 60 s (doble clic). Pasado el minuto, reconfirmar sí escribe evento y reinicia `marcado_en` (supuesto comunicado a Miguel: marcar reinicia el reloj de la caducidad).
- **Test gaps de r1:** `crm.leads.actualizado_en` sembrado en el pasado y comparado al segundo; `marcado_en` envejecido 2 min y reconfirmado; filas en `public.audit_log` con `usuario_id` del actor; analista desactivado tras marcar; parqueo apuntando a un analista; sin grants la API no lee y, con un grant de prueba deshecho, la RLS filtra.

## Evidencia de ejecución (banco Docker propio con el esquema de prod, versión final)
- Ciclo: migración PASS → repetida (PREFLIGHT se niega) → reversa PASS → reversa repetida (se niega) → migración PASS → registrar ×2 idempotente (md5 del archivo 8f4a4795bd8ede231ba6e9c1efebf0d6) → verificar (solo lectura) OK.
- Sintética: 75 de 75.
- Concurrencia (dos sesiones reales, script abajo): 5 de 5. Mutante «puerta sin potencial_bloquear_lead»: 3 fallas (V1 escribió `ok:estrella` durante la reasignación y durante el descarte). Mutante «reversa sin candados»: la reversa aprobó y borró la marca confirmada.
- Mutantes de la migración rechazados: privada sin revoke, `grant select … to authenticated`, `grant usage` en la secuencia, policy `using (true)`, disparador inmutable solo `before update`, sin disparador TRUNCATE, puerta INVOKER, bandera encendida, `private.rol_crm` alterado (PREFLIGHT). El mutante «tabla con otro dueño» no se pudo construir: `postgres` no puede ceder a `supabase_admin` (must be able to SET ROLE).
- Mutantes de lógica cazados por la sintética: cerrado pasa (3 fallas), parqueo sin exigir supervisor (1), token NULL (29), sin antirrebote (7), no reinicia el reloj (1), gerencia pasa en ayudante Y puerta (7). «Gerencia pasa» SOLO en el ayudante sobrevive: la puerta exige el rol antes (doble candado a propósito).
- `check:scripts` PASS, `node --check test-rls.mjs` PASS; `test:rls:preflight` NOT RUN (credenciales).

## Preguntas para refutar
1. ¿`FOR SHARE` sobre la fila del lead dentro de un INVOKER llamado desde un DEFINER cierra de verdad F1? ¿Hay algún escritor de `crm.leads` que cambie `vendedor_id`/`asignado_supervisor_id`/`etapa`/`activo` sin tomar un bloqueo de fila que conflicte con FOR SHARE (p. ej. vía otra tabla o un proceso que el candado no ve)? ¿Riesgo de interbloqueo con los disparadores de `crm.leads` o con procesos por lotes?
2. ¿La reversa con `for update` de la bandera + `lock table … access exclusive` en ese orden puede interbloquear con una marca en vuelo (que tiene el consultivo, FOR SHARE del lead, y RowExclusive de las tablas)?
3. ¿El postflight con `set_config('search_path','',true)` puede dar falso rojo en producción por diferencias de renderizado de `pg_policies.qual` o `pg_get_triggerdef` respecto del banco (misma versión 17.6)?
4. ¿El antirrebote de 60 s abre algún problema (p. ej. un cambio de supervisor que no deja evento, o una marca «reconfirmada» que no reinicia el reloj cuando debía)?
5. ¿Algo del bloque de la suite puede escribir o dar falso verde?

## Archivos (versión final)

### supabase/migrations/20260930213647_crm_potencial_lead.sql
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
-- CONCURRENCIA (Codex r1 F1): la autorización decisiva se evalúa DESPUÉS de bloquear la fila
--   del lead (FOR SHARE: una reasignación, cierre o desactivación en vuelo termina antes, o
--   espera a que la marca termine). La fase 2 (caducidad) debe tomar el MISMO candado
--   consultivo (hashtext('crm.lead_potencial'), hashtext(lead_id)) antes de escribir.
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
returns void
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
end;
$function$;
comment on function private.potencial_bloquear_lead(uuid) is
'Candado de la marca: consultivo por lead (hashtext(''crm.lead_potencial''), hashtext(lead_id)) + FOR SHARE de la fila del lead, hasta el final de la transacción. La caducidad (fase 2) debe tomar el mismo consultivo. Sin EXECUTE para la API.';

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
begin
  -- Reentrante: la puerta ya lo tomó; el núcleo no depende de ello.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.lead_potencial'), pg_catalog.hashtext(p_lead_id::text));

  select p.* into v_actual from crm.lead_potencial p where p.lead_id = p_lead_id;

  -- Doble clic: misma persona, mismo nivel, marca manual de hace menos de 60 s → no escribe.
  if v_actual.id is not null and v_actual.nivel = p_nivel and v_actual.origen = 'manual'
     and v_actual.marcado_por = p_actor and v_actual.marcado_en > pg_catalog.now() - interval '60 seconds' then
    return v_actual;
  end if;

  insert into crm.lead_potencial as p (lead_id, nivel, origen, marcado_por, marcado_en)
  values (p_lead_id, p_nivel, 'manual', p_actor, pg_catalog.now())
  on conflict (lead_id) do update
    set nivel = excluded.nivel,
        origen = 'manual',
        marcado_por = excluded.marcado_por,
        marcado_en = excluded.marcado_en
  returning p.* into v_fila;

  insert into crm.lead_potencial_eventos (lead_id, nivel_anterior, nivel_nuevo, motivo, por)
  values (p_lead_id, v_actual.nivel, p_nivel, 'manual', p_actor);

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
  perform private.potencial_bloquear_lead(p_lead_id);
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

### supabase/scripts/potencial-lead/reversa.sql
```sql
-- REVERSA de 20260930213647_crm_potencial_lead.
-- Solo mientras la función no se usó: se niega si hay una sola marca o evento, o si la bandera
-- está encendida (regla de la casa: en producción no se borra lo que tiene datos; con datos se
-- CIERRA con la bandera y se observa). Conserva la fila de schema_migrations: anotar la reversa
-- en MIGRACIONES.md.
-- Codex r1 F2: los candados se toman ANTES de comprobar el vacío y se sostienen hasta el commit.
-- Una marca en vuelo termina antes (y la reversa la ve y se niega) o espera a la reversa (y
-- muere porque la puerta ya no existe). Orden fijo: bandera, estado vigente, historial.
begin;
set local lock_timeout = '5s';
do $chk$
begin
  if (
    pg_catalog.to_regclass('crm.lead_potencial') is not null
    and pg_catalog.to_regclass('crm.lead_potencial_eventos') is not null
  ) is not true then
    raise exception 'REVERSA potencial_lead: la migración no está aplicada (faltan las tablas)';
  end if;
end;
$chk$;

select 1 from crm.multiempresa_flags where nombre = 'potencial_lead' for update;
lock table crm.lead_potencial, crm.lead_potencial_eventos in access exclusive mode;

do $vacio$
begin
  if (
    (select count(*) from crm.lead_potencial) = 0
    and (select count(*) from crm.lead_potencial_eventos) = 0
    and coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'potencial_lead'), false) = false
  ) is not true then
    raise exception 'REVERSA potencial_lead: hay marcas, eventos o la bandera está encendida; apaga la bandera y no borres datos';
  end if;
end;
$vacio$;

drop function crm.marcar_potencial_lead_fn(uuid, crm.nivel_potencial);
drop function private.potencial_marcar_nucleo(uuid, uuid, crm.nivel_potencial);
drop function private.potencial_rechazo(uuid, uuid);
drop function private.potencial_bloquear_lead(uuid);
drop table crm.lead_potencial_eventos;
drop table crm.lead_potencial;
drop function private.potencial_evento_inmutable();
drop type crm.nivel_potencial;
delete from crm.multiempresa_flags where nombre = 'potencial_lead' and activo = false;

do $post$
begin
  if (
    pg_catalog.to_regtype('crm.nivel_potencial') is null
    and pg_catalog.to_regclass('crm.lead_potencial') is null
    and pg_catalog.to_regclass('crm.lead_potencial_eventos') is null
    and not exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
                    where (n.nspname = 'crm' and p.proname = 'marcar_potencial_lead_fn')
                       or (n.nspname = 'private' and p.proname in ('potencial_rechazo', 'potencial_marcar_nucleo',
                                                                   'potencial_evento_inmutable', 'potencial_bloquear_lead')))
    and not exists (select 1 from crm.multiempresa_flags f where f.nombre = 'potencial_lead')
  ) is not true then
    raise exception 'REVERSA potencial_lead: quedaron objetos';
  end if;
  raise notice 'REVERSA potencial_lead OK: sin objetos ni bandera.';
end;
$post$;
commit;

```

### supabase/scripts/potencial-lead/prueba-concurrencia.sh
```bash
#!/usr/bin/env bash
# Prueba de CONCURRENCIA de 20260930213647_crm_potencial_lead (Codex r1 F1 y F2).
# SOLO en el banco Docker propio: crea un mundo sintético CONFIRMADO (ids fijos), corre dos
# sesiones de verdad que se cruzan y lo limpia al final. Nunca contra producción.
#
#   BANCO_CONTENEDOR=avancecorp-potencial-20260930 bash prueba-concurrencia.sh
#
# Casos:
#   A · reasignación en vuelo: T1 reasigna L1 de V1 a V2 y tarda; V1 intenta marcar en medio.
#       Esperado: V1 espera a T1 y recibe P0002 (antes del arreglo escribía con permiso caducado).
#   B · cierre en vuelo: T1 descarta L1 y tarda; V1 marca en medio → 22023.
#   C · reversa contra una marca sin confirmar: V1 marca y tarda en confirmar; otra sesión apaga la
#       bandera; la reversa corre en medio. Esperado: la reversa espera y se NIEGA (hay marcas).
set -euo pipefail
C="${BANCO_CONTENEDOR:-avancecorp-potencial-20260930}"
DIR="$(cd "$(dirname "$0")" && pwd)"
psql_as() { # $1 = usuario, resto = argumentos de psql
  local u="$1"; shift
  docker exec -i -e PGPASSWORD=postgres "$C" psql -U "$u" -h 127.0.0.1 -d postgres -v ON_ERROR_STOP=1 -qAt "$@"
}
V1=00000000-0000-4000-8000-00000000c0a1; V2=00000000-0000-4000-8000-00000000c0a2
S1=00000000-0000-4000-8000-00000000c0b1; S2=00000000-0000-4000-8000-00000000c0b2
L1=00000000-0000-4000-8000-00000000c0c1
ok=0; mal=0
esperar() { # $1 caso, $2 esperado (regex), $3 obtenido
  if [[ "$3" =~ $2 ]]; then echo "  ✓ $1"; ok=$((ok+1)); else echo "  ✗ $1 — esperado /$2/, obtenido: $3"; mal=$((mal+1)); fi
}

mundo() {
  psql_as supabase_admin <<SQL
set session_replication_role = replica;
insert into auth.users (id, email) values ('$V1','cv1@potencial.banco'),('$V2','cv2@potencial.banco'),('$S1','cs1@potencial.banco'),('$S2','cs2@potencial.banco') on conflict do nothing;
insert into public.perfiles (id, nombre_completo, rol, activo) values ('$V1','CONC V1','analista',true),('$V2','CONC V2','analista',true),('$S1','CONC S1','analista',true),('$S2','CONC S2','analista',true) on conflict (id) do nothing;
insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo) values ('$S1','supervisor',null,true),('$S2','supervisor',null,true),('$V1','vendedor','$S1',true),('$V2','vendedor','$S2',true) on conflict (perfil_id) do nothing;
delete from crm.lead_potencial where lead_id = '$L1';
delete from crm.lead_potencial_eventos where lead_id = '$L1';
insert into crm.leads (id, nombre_completo, telefono, origen, monto_estimado, moneda, etapa, vendedor_id, activo)
  values ('$L1','CONC L1','+51987659001','landing',50000,'PEN','contactado','$V1',true)
  on conflict (id) do update set vendedor_id = '$V1', asignado_supervisor_id = null, etapa = 'contactado', motivo_descarte = null, activo = true;
set session_replication_role = origin;
update crm.multiempresa_flags set activo = true where nombre = 'potencial_lead';
SQL
}
limpiar() {
  psql_as supabase_admin <<SQL
set session_replication_role = replica;
delete from crm.lead_potencial_eventos where lead_id = '$L1';
delete from crm.lead_potencial where lead_id = '$L1';
delete from crm.leads where id = '$L1';
delete from crm.equipo where perfil_id in ('$V1','$V2','$S1','$S2');
delete from public.perfiles where id in ('$V1','$V2','$S1','$S2');
delete from auth.users where id in ('$V1','$V2','$S1','$S2');
set session_replication_role = origin;
update crm.multiempresa_flags set activo = false where nombre = 'potencial_lead';
SQL
}
marcar_como() { # $1 actor, $2 nivel → imprime ok:<nivel> o el SQLSTATE
  psql_as supabase_admin <<SQL 2>&1 | tail -1
do \$m\$ declare v jsonb; begin
  perform set_config('request.jwt.claim.sub', '$1', true);
  perform set_config('request.jwt.claims', json_build_object('sub', '$1', 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin
    v := crm.marcar_potencial_lead_fn('$L1', '$2');
    raise notice 'RESULTADO ok:%', v ->> 'nivel';
  exception when others then
    raise notice 'RESULTADO %', sqlstate;
  end;
end \$m\$;
SQL
}

echo "A · reasignación en vuelo"
mundo
( psql_as supabase_admin -c "begin; set local session_replication_role = replica; update crm.leads set vendedor_id = '$V2' where id = '$L1'; select pg_sleep(3); commit;" >/dev/null ) &
sleep 1
r=$(marcar_como "$V1" estrella); wait
esperar "V1 marca mientras reasignan L1 a V2 → P0002" 'RESULTADO P0002' "$r"
esperar "no quedó marca escrita con el permiso caducado" '^0$' "$(psql_as supabase_admin -c "select count(*) from crm.lead_potencial where lead_id = '$L1'")"

echo "B · cierre en vuelo"
mundo
( psql_as supabase_admin -c "begin; set local session_replication_role = replica; update crm.leads set etapa = 'descartado', motivo_descarte = 'sin_interes' where id = '$L1'; select pg_sleep(3); commit;" >/dev/null ) &
sleep 1
r=$(marcar_como "$V1" estrella); wait
esperar "V1 marca mientras descartan L1 → 22023" 'RESULTADO 22023' "$r"

echo "C · reversa contra una marca sin confirmar"
mundo
( psql_as supabase_admin -c "begin; select set_config('request.jwt.claim.sub', '$V1', true), set_config('request.jwt.claims', json_build_object('sub', '$V1', 'role', 'authenticated')::text, true); set local role authenticated; select crm.marcar_potencial_lead_fn('$L1', 'estrella'); select pg_sleep(4); commit;" >/dev/null ) &
sleep 1
psql_as supabase_admin -c "update crm.multiempresa_flags set activo = false where nombre = 'potencial_lead';" >/dev/null
r=$(docker exec -i -e PGPASSWORD=postgres "$C" psql -U postgres -h 127.0.0.1 -d postgres -v ON_ERROR_STOP=1 -qAt -c "$(cat "$DIR/reversa.sql")" 2>&1 | grep -m1 -o 'ERROR:.*\|NOTICE:.*REVERSA.*' || true); wait || true
esperar "la reversa espera a la marca y se niega" 'REVERSA potencial_lead: hay marcas' "$r"
esperar "la marca confirmada sigue en su tabla" '^1$' "$(psql_as supabase_admin -c "select count(*) from crm.lead_potencial where lead_id = '$L1'" 2>&1 | tail -1)"

limpiar
echo "CONCURRENCIA potencial_lead: $ok OK, $mal FALLAS"
[ "$mal" -eq 0 ]

```

### supabase/scripts/potencial-lead/prueba-sintetica.sql
```sql
-- Prueba sintética de 20260930213647_crm_potencial_lead.
-- SOLO en un banco (Docker propio con el esquema de producción), como supabase_admin. Todo
-- ocurre en UNA transacción que termina en raise: no deja filas, ni actores, ni la bandera.
-- ⚠️ Nunca se llama a una función sin EXECUTE bajo `set role` (tumba Postgres 17.6 con
-- plan_filter): los permisos de los ayudantes privados se leen del catálogo.
--
-- Mundo: gerencia G · supervisor S1 con sub-supervisor S1n · analista V1 (de S1) y V1n (de
-- S1n) · supervisor S2 con analista V2 · coordinador C · directorio D · X con equipo
-- inactivo. Leads: L1 (V1), L1n (V1n), L2 (V2), LP (parqueado en S1), LC (V1 convertido),
-- LD (V1 descartado), LI (V1 inactivo) y un id que no existe.
begin;
set local lock_timeout = '5s';

create temp table act (k text primary key, id uuid not null default gen_random_uuid()) on commit drop;
insert into act (k) values ('G'), ('S1'), ('S1n'), ('V1'), ('V1n'), ('S2'), ('V2'), ('C'), ('D'), ('X');
create temp table lds (k text primary key, id uuid not null default gen_random_uuid()) on commit drop;
insert into lds (k) values ('L1'), ('L1n'), ('L2'), ('LP'), ('LC'), ('LD'), ('LI'), ('L3'), ('LPV'), ('NADA');
create temp table res (n serial, caso text, esperado text, obtenido text) on commit drop;

create function pg_temp.a(p_k text) returns uuid language sql as $$ select id from act where k = p_k $$;
create function pg_temp.l(p_k text) returns uuid language sql as $$ select id from lds where k = p_k $$;
create function pg_temp.esperar(p_caso text, p_esperado text, p_obtenido text) returns void language sql as $$
  insert into res (caso, esperado, obtenido) values (p_caso, p_esperado, coalesce(p_obtenido, '(null)'))
$$;

-- Fixtures sin disparadores (solo filas que cumplen los CHECK).
set local session_replication_role = replica;
insert into auth.users (id, email) select id, lower(k) || '@potencial.banco' from act;
insert into public.perfiles (id, nombre_completo, rol, activo)
  select id, 'POTENCIAL ' || k, case k when 'D' then 'directorio' when 'G' then 'admin' else 'analista' end, true from act;
insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo) values
  (pg_temp.a('G'), 'gerencia', null, true),
  (pg_temp.a('S1'), 'supervisor', null, true),
  (pg_temp.a('S1n'), 'supervisor', pg_temp.a('S1'), true),
  (pg_temp.a('V1'), 'vendedor', pg_temp.a('S1'), true),
  (pg_temp.a('V1n'), 'vendedor', pg_temp.a('S1n'), true),
  (pg_temp.a('S2'), 'supervisor', null, true),
  (pg_temp.a('V2'), 'vendedor', pg_temp.a('S2'), true),
  (pg_temp.a('C'), 'coordinador', null, true),
  (pg_temp.a('D'), 'directorio', null, true),
  (pg_temp.a('X'), 'vendedor', pg_temp.a('S1'), false);
insert into crm.leads (id, nombre_completo, telefono, origen, monto_estimado, moneda, etapa, vendedor_id, asignado_supervisor_id, activo, motivo_descarte) values
  (pg_temp.l('L1'),  'POTENCIAL L1',  '+51987650001', 'landing', 50000, 'PEN', 'contactado', pg_temp.a('V1'),  null, true, null),
  (pg_temp.l('L1n'), 'POTENCIAL L1N', '+51987650002', 'landing', 15000, 'PEN', 'nuevo',      pg_temp.a('V1n'), null, true, null),
  (pg_temp.l('L2'),  'POTENCIAL L2',  '+51987650003', 'landing', 30000, 'PEN', 'contactado', pg_temp.a('V2'),  null, true, null),
  (pg_temp.l('LP'),  'POTENCIAL LP',  '+51987650004', 'landing', 12000, 'PEN', 'nuevo',      null, pg_temp.a('S1'), true, null),
  (pg_temp.l('LC'),  'POTENCIAL LC',  '+51987650005', 'landing', 20000, 'PEN', 'convertido', pg_temp.a('V1'),  null, true, null),
  (pg_temp.l('LD'),  'POTENCIAL LD',  '+51987650006', 'landing', 20000, 'PEN', 'descartado', pg_temp.a('V1'),  null, true, 'sin_interes'),
  (pg_temp.l('LI'),  'POTENCIAL LI',  '+51987650007', 'landing', 20000, 'PEN', 'contactado', pg_temp.a('V1'),  null, false, null),
  (pg_temp.l('L3'),  'POTENCIAL L3',  '+51987650008', 'landing', 20000, 'PEN', 'contactado', pg_temp.a('V1'),  null, true, null),
  (pg_temp.l('LPV'), 'POTENCIAL LPV', '+51987650009', 'landing', 20000, 'PEN', 'nuevo',      null, pg_temp.a('V1'), true, null);
-- actualizado_en sembrado en el pasado: si marcar tocara crm.leads, cambiaría (Codex r1).
update crm.leads set actualizado_en = '2026-01-02 03:04:05+00' where id = pg_temp.l('L1');
set local session_replication_role = origin;

-- Fija la identidad de la sesión. Se escriben las DOS formas: el auth.uid() de producción lee
-- request.jwt.claims (->> 'sub') y el de esta imagen del banco solo request.jwt.claim.sub.
create function pg_temp.sesion(p_actor uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', coalesce(p_actor::text, ''), true),
         set_config('request.jwt.claims',
           case when p_actor is null then '' else json_build_object('sub', p_actor, 'role', 'authenticated')::text end, true);
$$;

-- Llamar a la puerta como un actor autenticado; devuelve 'ok:<nivel>' o el SQLSTATE.
create function pg_temp.marcar(p_actor uuid, p_lead uuid, p_nivel text) returns text language plpgsql as $f$
declare v jsonb;
begin
  perform pg_temp.sesion(p_actor);
  set local role authenticated;
  begin
    v := crm.marcar_potencial_lead_fn(p_lead, p_nivel::crm.nivel_potencial);
    reset role;
    return 'ok:' || (v ->> 'nivel');
  exception when others then
    reset role;
    return sqlstate;
  end;
end $f$;

-- Cuántas filas de la marca ve un actor para un lead (RLS).
create function pg_temp.ve(p_actor uuid, p_lead uuid) returns text language plpgsql as $f$
declare n int; m int;
begin
  perform pg_temp.sesion(p_actor);
  set local role authenticated;
  begin
    select count(*) into n from crm.lead_potencial where lead_id = p_lead;
    select count(*) into m from crm.lead_potencial_eventos where lead_id = p_lead;
  exception when others then
    reset role;
    return sqlstate;
  end;
  reset role;
  return n || '/' || m;
end $f$;

-- Una escritura directa por la API (sin la puerta) como un actor; devuelve 'ok' o el SQLSTATE.
create function pg_temp.escribe(p_actor uuid, p_sql text) returns text language plpgsql as $f$
begin
  perform pg_temp.sesion(p_actor);
  set local role authenticated;
  begin
    execute p_sql;
    reset role;
    return 'ok';
  exception when others then
    reset role;
    return sqlstate;
  end;
end $f$;

-- Una operación como supabase_admin; devuelve 'ok' o el SQLSTATE.
create function pg_temp.admin(p_sql text) returns text language plpgsql as $f$
begin
  execute p_sql;
  return 'ok';
exception when others then
  return sqlstate;
end $f$;

do $prueba$
declare
  v_actividades_antes int;
  v_marcado_en timestamptz;
  v_n int;
begin
  -- ── Catálogo: ayudantes privados sin EXECUTE para la API; puerta solo authenticated ──
  perform pg_temp.esperar('privadas sin EXECUTE de anon/authenticated/service_role/PUBLIC', '0', (
    select count(*)::text from pg_proc p, aclexplode(p.proacl) x
    where p.oid in ('private.potencial_rechazo(uuid,uuid)'::regprocedure,
                    'private.potencial_marcar_nucleo(uuid,uuid,crm.nivel_potencial)'::regprocedure,
                    'private.potencial_bloquear_lead(uuid)'::regprocedure,
                    'private.potencial_evento_inmutable()'::regprocedure)
      and x.grantee <> 'postgres'::regrole));
  perform pg_temp.esperar('puerta: EXECUTE solo postgres y authenticated', 'authenticated,postgres', (
    select string_agg(x.grantee::regrole::text, ',' order by x.grantee::regrole::text)
    from pg_proc p, aclexplode(p.proacl) x
    where p.oid = 'crm.marcar_potencial_lead_fn(uuid,crm.nivel_potencial)'::regprocedure and x.privilege_type = 'EXECUTE'));
  perform pg_temp.esperar('tablas sin grants para la API (ni SELECT)', '0', (
    select count(*)::text from unnest(array['anon','authenticated','service_role']) r(rol),
      unnest(array['crm.lead_potencial','crm.lead_potencial_eventos']) t(tabla),
      unnest(array['SELECT','INSERT','UPDATE','DELETE','TRUNCATE']) x(priv)
    where has_table_privilege(r.rol, t.tabla, x.priv)));
  perform pg_temp.esperar('bandera nace apagada', 'false', (select activo::text from crm.multiempresa_flags where nombre = 'potencial_lead'));

  -- ── Bandera APAGADA: quien pasa rol y ámbito recibe 55000; los demás, su rechazo ──
  perform pg_temp.esperar('sin sesión', '42501', pg_temp.marcar(null, pg_temp.l('L1'), 'estrella'));
  perform pg_temp.esperar('V1 sin lead (null)', '22023', pg_temp.marcar(pg_temp.a('V1'), null, 'estrella'));
  perform pg_temp.esperar('V1 → su lead L1 (pasa, bandera apagada)', '55000', pg_temp.marcar(pg_temp.a('V1'), pg_temp.l('L1'), 'estrella'));
  perform pg_temp.esperar('V1 → L2 de otro equipo', 'P0002', pg_temp.marcar(pg_temp.a('V1'), pg_temp.l('L2'), 'estrella'));
  perform pg_temp.esperar('V1 → LP parqueado en su supervisor', 'P0002', pg_temp.marcar(pg_temp.a('V1'), pg_temp.l('LP'), 'estrella'));
  perform pg_temp.esperar('V1 → LPV parqueado «en él» (solo un supervisor marca parqueos)', 'P0002', pg_temp.marcar(pg_temp.a('V1'), pg_temp.l('LPV'), 'estrella'));
  perform pg_temp.esperar('V1 → L1n de otro analista del mismo árbol', 'P0002', pg_temp.marcar(pg_temp.a('V1'), pg_temp.l('L1n'), 'estrella'));
  perform pg_temp.esperar('V1 → LC convertido', '22023', pg_temp.marcar(pg_temp.a('V1'), pg_temp.l('LC'), 'estrella'));
  perform pg_temp.esperar('V1 → LD descartado', '22023', pg_temp.marcar(pg_temp.a('V1'), pg_temp.l('LD'), 'estrella'));
  perform pg_temp.esperar('V1 → LI inactivo', 'P0002', pg_temp.marcar(pg_temp.a('V1'), pg_temp.l('LI'), 'estrella'));
  perform pg_temp.esperar('V1 → lead inexistente', 'P0002', pg_temp.marcar(pg_temp.a('V1'), pg_temp.l('NADA'), 'estrella'));
  perform pg_temp.esperar('S1 → L1 de su analista', '55000', pg_temp.marcar(pg_temp.a('S1'), pg_temp.l('L1'), 'estrella'));
  perform pg_temp.esperar('S1 → L1n de su sub-supervisor', '55000', pg_temp.marcar(pg_temp.a('S1'), pg_temp.l('L1n'), 'estrella'));
  perform pg_temp.esperar('S1 → LP parqueado en su bandeja', '55000', pg_temp.marcar(pg_temp.a('S1'), pg_temp.l('LP'), 'estrella'));
  perform pg_temp.esperar('S1 → L2 de otro supervisor', 'P0002', pg_temp.marcar(pg_temp.a('S1'), pg_temp.l('L2'), 'estrella'));
  perform pg_temp.esperar('S1n → L1 de su jefe (no es su árbol)', 'P0002', pg_temp.marcar(pg_temp.a('S1n'), pg_temp.l('L1'), 'estrella'));
  perform pg_temp.esperar('S2 → L1', 'P0002', pg_temp.marcar(pg_temp.a('S2'), pg_temp.l('L1'), 'estrella'));
  perform pg_temp.esperar('gerencia → L1', '42501', pg_temp.marcar(pg_temp.a('G'), pg_temp.l('L1'), 'estrella'));
  perform pg_temp.esperar('coordinador → L1', '42501', pg_temp.marcar(pg_temp.a('C'), pg_temp.l('L1'), 'estrella'));
  perform pg_temp.esperar('directorio → L1', '42501', pg_temp.marcar(pg_temp.a('D'), pg_temp.l('L1'), 'estrella'));
  perform pg_temp.esperar('X con equipo inactivo → L1', '42501', pg_temp.marcar(pg_temp.a('X'), pg_temp.l('L1'), 'estrella'));
  perform pg_temp.esperar('nivel inválido', '22P02', pg_temp.marcar(pg_temp.a('V1'), pg_temp.l('L1'), 'dorado'));
  perform pg_temp.esperar('con la bandera apagada no se escribió nada', '0', (select (count(*) + (select count(*) from crm.lead_potencial_eventos))::text from crm.lead_potencial));

  -- ── Escritura directa por la API: siempre denegada (sin grants) ──
  perform pg_temp.esperar('V1 INSERT directo en lead_potencial', '42501', pg_temp.escribe(pg_temp.a('V1'),
    format('insert into crm.lead_potencial (lead_id, nivel, origen, marcado_por, marcado_en) values (%L, ''estrella'', ''manual'', %L, now())', pg_temp.l('L1'), pg_temp.a('V1'))));
  perform pg_temp.esperar('V1 INSERT directo en lead_potencial_eventos', '42501', pg_temp.escribe(pg_temp.a('V1'),
    format('insert into crm.lead_potencial_eventos (lead_id, nivel_nuevo, motivo, por) values (%L, ''estrella'', ''manual'', %L)', pg_temp.l('L1'), pg_temp.a('V1'))));
  perform pg_temp.esperar('gerencia UPDATE directo en lead_potencial', '42501', pg_temp.escribe(pg_temp.a('G'), 'update crm.lead_potencial set nivel = ''frio'''));

  -- ── Bandera ENCENDIDA (como lo hará la fase 3) ──
  update crm.multiempresa_flags set activo = true where nombre = 'potencial_lead';
  select count(*) into v_actividades_antes from crm.actividades a where a.lead_id = pg_temp.l('L1');

  perform pg_temp.esperar('V1 marca L1 estrella', 'ok:estrella', pg_temp.marcar(pg_temp.a('V1'), pg_temp.l('L1'), 'estrella'));
  perform pg_temp.esperar('primer evento: null → estrella por V1', 'null>estrella/manual/V1', (
    select coalesce(e.nivel_anterior::text, 'null') || '>' || e.nivel_nuevo || '/' || e.motivo || '/' || (select k from act where id = e.por)
    from crm.lead_potencial_eventos e where e.lead_id = pg_temp.l('L1') order by e.orden limit 1));
  select p.marcado_en into v_marcado_en from crm.lead_potencial p where p.lead_id = pg_temp.l('L1');

  perform pg_temp.esperar('V1 cambia L1 a tibio', 'ok:tibio', pg_temp.marcar(pg_temp.a('V1'), pg_temp.l('L1'), 'tibio'));
  perform pg_temp.esperar('S1 (su supervisor) vuelve L1 a estrella', 'ok:estrella', pg_temp.marcar(pg_temp.a('S1'), pg_temp.l('L1'), 'estrella'));
  perform pg_temp.esperar('S1 doble clic (mismo nivel, <60 s) responde', 'ok:estrella', pg_temp.marcar(pg_temp.a('S1'), pg_temp.l('L1'), 'estrella'));
  perform pg_temp.esperar('el doble clic no escribe evento', 'null>estrella,estrella>tibio,tibio>estrella', (
    select string_agg(coalesce(e.nivel_anterior::text, 'null') || '>' || e.nivel_nuevo, ',' order by e.orden)
    from crm.lead_potencial_eventos e where e.lead_id = pg_temp.l('L1')));
  -- La marca de S1 «envejece» 2 minutos: reconfirmar YA escribe y reinicia el reloj.
  update crm.lead_potencial set marcado_en = now() - interval '2 minutes' where lead_id = pg_temp.l('L1');
  select p.marcado_en into v_marcado_en from crm.lead_potencial p where p.lead_id = pg_temp.l('L1');
  perform pg_temp.esperar('S1 reconfirma estrella pasado el minuto', 'ok:estrella', pg_temp.marcar(pg_temp.a('S1'), pg_temp.l('L1'), 'estrella'));
  perform pg_temp.esperar('reconfirmar reinicia marcado_en', 'true', (
    select (p.marcado_en > v_marcado_en)::text from crm.lead_potencial p where p.lead_id = pg_temp.l('L1')));
  perform pg_temp.esperar('estado vigente de L1: una fila, estrella, manual, por S1', '1|estrella|manual|S1', (
    select count(*) || '|' || max(p.nivel::text) || '|' || max(p.origen) || '|' || max((select k from act where id = p.marcado_por))
    from crm.lead_potencial p where p.lead_id = pg_temp.l('L1')));
  perform pg_temp.esperar('historial de L1 en orden', 'null>estrella,estrella>tibio,tibio>estrella,estrella>estrella', (
    select string_agg(coalesce(e.nivel_anterior::text, 'null') || '>' || e.nivel_nuevo, ',' order by e.orden)
    from crm.lead_potencial_eventos e where e.lead_id = pg_temp.l('L1')));
  perform pg_temp.esperar('marcar NO toca crm.leads.actualizado_en (sembrado en 2026-01-02)', '2026-01-02 03:04:05+00', (
    select to_char(l.actualizado_en at time zone 'UTC', 'YYYY-MM-DD HH24:MI:SS') || '+00' from crm.leads l where l.id = pg_temp.l('L1')));
  perform pg_temp.esperar('marcar NO crea actividades (no es gestión)', v_actividades_antes::text, (
    select count(*)::text from crm.actividades a where a.lead_id = pg_temp.l('L1')));

  perform pg_temp.esperar('S1 marca LP parqueado', 'ok:frio', pg_temp.marcar(pg_temp.a('S1'), pg_temp.l('LP'), 'frio'));
  perform pg_temp.esperar('V1 sigue sin poder con L2', 'P0002', pg_temp.marcar(pg_temp.a('V1'), pg_temp.l('L2'), 'estrella'));
  perform pg_temp.esperar('gerencia sigue sin marcar', '42501', pg_temp.marcar(pg_temp.a('G'), pg_temp.l('L1'), 'frio'));
  perform pg_temp.esperar('V1 sigue sin marcar un convertido', '22023', pg_temp.marcar(pg_temp.a('V1'), pg_temp.l('LC'), 'estrella'));

  -- ── Lectura: sin grants la API no lee; con un grant de prueba (deshecho) la RLS filtra ──
  perform pg_temp.esperar('sin grant: V1 no lee la tabla directo', '42501', pg_temp.ve(pg_temp.a('V1'), pg_temp.l('L1')));
  perform pg_temp.esperar('sin grant: gerencia tampoco', '42501', pg_temp.ve(pg_temp.a('G'), pg_temp.l('L1')));
  grant select on crm.lead_potencial, crm.lead_potencial_eventos to authenticated;
  perform pg_temp.esperar('V1 ve la marca de L1 (vigente/eventos)', '1/4', pg_temp.ve(pg_temp.a('V1'), pg_temp.l('L1')));
  perform pg_temp.esperar('S1 ve la marca de L1', '1/4', pg_temp.ve(pg_temp.a('S1'), pg_temp.l('L1')));
  perform pg_temp.esperar('gerencia ve la marca de L1', '1/4', pg_temp.ve(pg_temp.a('G'), pg_temp.l('L1')));
  perform pg_temp.esperar('directorio ve la marca de L1', '1/4', pg_temp.ve(pg_temp.a('D'), pg_temp.l('L1')));
  perform pg_temp.esperar('V2 NO ve la marca de L1', '0/0', pg_temp.ve(pg_temp.a('V2'), pg_temp.l('L1')));
  perform pg_temp.esperar('S2 NO ve la marca de L1', '0/0', pg_temp.ve(pg_temp.a('S2'), pg_temp.l('L1')));
  perform pg_temp.esperar('coordinador NO ve la marca de L1', '0/0', pg_temp.ve(pg_temp.a('C'), pg_temp.l('L1')));
  perform pg_temp.esperar('V1 NO ve la marca de LP (parqueado)', '0/0', pg_temp.ve(pg_temp.a('V1'), pg_temp.l('LP')));
  perform pg_temp.esperar('S1 ve la marca de LP', '1/1', pg_temp.ve(pg_temp.a('S1'), pg_temp.l('LP')));

  -- ── Historial inmutable (incluso para el superusuario) ──
  perform pg_temp.esperar('UPDATE del historial', 'P0409', pg_temp.admin('update crm.lead_potencial_eventos set motivo = ''caducidad'', por = null'));
  perform pg_temp.esperar('DELETE del historial', 'P0409', pg_temp.admin('delete from crm.lead_potencial_eventos'));
  perform pg_temp.esperar('TRUNCATE del historial', 'P0409', pg_temp.admin('truncate crm.lead_potencial_eventos'));
  perform pg_temp.esperar('evento manual sin autor', '23514', pg_temp.admin(format(
    'insert into crm.lead_potencial_eventos (lead_id, nivel_nuevo, motivo, por) values (%L, ''frio'', ''manual'', null)', pg_temp.l('L1'))));
  perform pg_temp.esperar('segunda fila vigente para el mismo lead', '23505', pg_temp.admin(format(
    'insert into crm.lead_potencial (lead_id, nivel, origen, marcado_por, marcado_en) values (%L, ''frio'', ''manual'', %L, now())', pg_temp.l('L1'), pg_temp.a('V1'))));

  -- ── La marca es del lead: viaja al reasignar ──
  set local session_replication_role = replica;
  update crm.leads set vendedor_id = pg_temp.a('V2') where id = pg_temp.l('L1');
  set local session_replication_role = origin;
  perform pg_temp.esperar('tras reasignar L1 a V2: V2 ve la marca', '1/4', pg_temp.ve(pg_temp.a('V2'), pg_temp.l('L1')));
  perform pg_temp.esperar('tras reasignar: V1 ya no la ve', '0/0', pg_temp.ve(pg_temp.a('V1'), pg_temp.l('L1')));
  perform pg_temp.esperar('tras reasignar: V2 puede marcar L1', 'ok:tibio', pg_temp.marcar(pg_temp.a('V2'), pg_temp.l('L1'), 'tibio'));
  perform pg_temp.esperar('tras reasignar: V1 ya no puede', 'P0002', pg_temp.marcar(pg_temp.a('V1'), pg_temp.l('L1'), 'estrella'));
  perform pg_temp.esperar('tras reasignar: S1 ya no puede', 'P0002', pg_temp.marcar(pg_temp.a('S1'), pg_temp.l('L1'), 'estrella'));
  perform pg_temp.esperar('tras reasignar: S2 (nuevo supervisor) sí puede', 'ok:estrella', pg_temp.marcar(pg_temp.a('S2'), pg_temp.l('L1'), 'estrella'));

  -- ── Analista desactivado tras marcar: ya no marca ni ve ──
  perform pg_temp.esperar('V1 marca L3', 'ok:tibio', pg_temp.marcar(pg_temp.a('V1'), pg_temp.l('L3'), 'tibio'));
  set local session_replication_role = replica;
  update crm.equipo set activo = false where perfil_id = pg_temp.a('V1');
  set local session_replication_role = origin;
  perform pg_temp.esperar('V1 desactivado ya no marca L3', '42501', pg_temp.marcar(pg_temp.a('V1'), pg_temp.l('L3'), 'estrella'));
  perform pg_temp.esperar('V1 desactivado ya no ve la marca de L3', '0/0', pg_temp.ve(pg_temp.a('V1'), pg_temp.l('L3')));
  perform pg_temp.esperar('S1 sí la ve y la puede cambiar', 'ok:frio', pg_temp.marcar(pg_temp.a('S1'), pg_temp.l('L3'), 'frio'));

  -- ── Auditoría: filas en public.audit_log con su autor ──
  perform pg_temp.esperar('bitácora: V1 escribió en lead_potencial y en su historial', 'true', (
    select (count(*) filter (where a.tabla = 'crm.lead_potencial') > 0
            and count(*) filter (where a.tabla = 'crm.lead_potencial_eventos') > 0)::text
    from public.audit_log a where a.usuario_id = pg_temp.a('V1')));
  perform pg_temp.esperar('bitácora: S1 figura como autor de sus marcas', 'true', (
    select (count(*) > 0)::text from public.audit_log a
    where a.usuario_id = pg_temp.a('S1') and a.tabla = 'crm.lead_potencial'));
  -- ── Auditoría: las escrituras dejaron rastro en la bitácora ──
  select count(*) into v_n from pg_trigger t
  where t.tgrelid in ('crm.lead_potencial'::regclass, 'crm.lead_potencial_eventos'::regclass)
    and t.tgname like 'trg_audit_%' and t.tgenabled = 'O';
  perform pg_temp.esperar('dos disparadores de auditoría activos', '2', v_n::text);

  -- ── Veredicto (el raise deshace todo) ──
  select count(*) into v_n from res where esperado is distinct from obtenido;
  if v_n = 0 then
    raise exception 'SINTETICA potencial_lead: % de % OK', (select count(*) from res), (select count(*) from res)
      using errcode = 'P0001';
  else
    raise exception 'SINTETICA potencial_lead: % FALLAS de %: %', v_n, (select count(*) from res),
      (select string_agg(n || ' ' || caso || ' → esperado ' || esperado || ', obtenido ' || obtenido, ' | ' order by n)
       from res where esperado is distinct from obtenido)
      using errcode = 'P0001';
  end if;
end;
$prueba$;
rollback;

```

### supabase/scripts/test-rls.mjs — bloque testPotencialLead
```js
// ── Potencial del lead (20260930213647): puerta crm.marcar_potencial_lead_fn ──────────────────
// Solo rechazos: con la bandera 'potencial_lead' APAGADA (así nace) nadie escribe. Quien pasa rol y
// ámbito recibe 55000 «todavía no está activada»: ese rechazo ES el positivo sin escribir (la puerta
// valida sesión → rol → candados → ámbito → etapa y solo después mira la bandera). Las escrituras,
// el historial inmutable, la reasignación, el doble clic y que marcar no toca crm.leads ni
// crm.actividades los prueba supabase/scripts/potencial-lead/prueba-sintetica.sql (75 casos, deshecha);
// las carreras, prueba-concurrencia.sh. Los casos 22023 (convertido/descartado) y P0002 por lead
// inactivo solo viven en la sintética: fixtures.mjs no tiene esos leads.
// Contrato (Codex r1 F4): el bloque NO llama a la puerta si la bandera está encendida (la lee fuera
// de banda antes): con la bandera encendida los «positivos» escribirían. Salto RUIDOSO si la puerta
// no está en esta base o falta la vía fuera de banda; con CRM_RLS_EXIGE_POTENCIAL=1 es un FALLO.
async function testPotencialLead(sessions, seed) {
  console.log('\n— Potencial del lead: puerta de la marca (rechazos, sin escribir) —');
  const saltar = (msg) => {
    if (process.env.CRM_RLS_EXIGE_POTENCIAL === '1') fail(msg);
    else console.log(`  ${msg}`);
  };
  let aplicada;
  let encendida;
  try {
    aplicada = contarFueraDeBanda('potencial: puerta aplicada',
      `select (to_regprocedure('crm.marcar_potencial_lead_fn(uuid,crm.nivel_potencial)') is not null)::int`);
    encendida = aplicada === 1 ? contarFueraDeBanda('potencial: bandera',
      `select coalesce((select activo::int from crm.multiempresa_flags where nombre = 'potencial_lead'), 0)`) : 0;
  } catch (error) {
    saltar(`⚠ Potencial del lead SALTADO: sin vía fuera de banda para leer la bandera (${error?.message ?? String(error)})`);
    return;
  }
  if (aplicada !== 1) {
    saltar('⚠ crm.marcar_potencial_lead_fn NO desplegada en esta base: bloque de Potencial del lead SALTADO (no probado)');
    return;
  }
  if (encendida !== 0) {
    fail('potencial: la bandera potencial_lead está ENCENDIDA; este bloque no corre para no escribir marcas');
    return;
  }

  const FN = 'marcar_potencial_lead_fn';
  const idDe = (clave) => seed.leadByName.get(LEAD_BY_KEY[clave].name)?.id;
  const marcarId = (cliente, leadId, nivel = 'estrella') => cliente.schema('crm').rpc(FN, { p_lead_id: leadId, p_nivel: nivel });
  const marcar = (cliente, clave, nivel = 'estrella') => marcarId(cliente, idDe(clave), nivel);
  const APAGADA = /todav[ií]a no est[aá] activada/i;
  const FUERA = /no encontrado o fuera de tu [aá]mbito/i;
  const ROL = /solo el analista del lead o su supervisor/i;
  const DENEGADO = /permission denied|denegado/i;

  // Pasan rol y ámbito → mueren en la bandera (el positivo sin escribir).
  await expectExpectedFailure('potencial vend1 → su lead (juan) llega a la bandera', marcar(sessions.vend1.client, 'juan'), ['55000'], APAGADA);
  await expectExpectedFailure('potencial sup1 → lead de su analista (juan) llega a la bandera', marcar(sessions.sup1.client, 'juan'), ['55000'], APAGADA);
  await expectExpectedFailure('potencial sup1 → lead de su subárbol (carlos) llega a la bandera', marcar(sessions.sup1.client, 'carlos'), ['55000'], APAGADA);
  await expectExpectedFailure('potencial sup1 → lead parqueado en su bandeja (luis) llega a la bandera', marcar(sessions.sup1.client, 'luis'), ['55000'], APAGADA);
  await expectExpectedFailure('potencial sup2 → lead parqueado en su bandeja (rosa) llega a la bandera', marcar(sessions.sup2.client, 'rosa'), ['55000'], APAGADA);
  await expectExpectedFailure('potencial sup2 → lead de su analista inactivo (inactiveOwned) llega a la bandera', marcar(sessions.sup2.client, 'inactiveOwned'), ['55000'], APAGADA);
  // Fuera de ámbito: P0002 (no revela si el lead existe).
  await expectExpectedFailure('potencial vend1 → lead de otro equipo (ana) → P0002', marcar(sessions.vend1.client, 'ana'), ['P0002'], FUERA);
  await expectExpectedFailure('potencial vend1 → lead parqueado (luis) → P0002', marcar(sessions.vend1.client, 'luis'), ['P0002'], FUERA);
  await expectExpectedFailure('potencial vend3 → lead de vend1 (juan) → P0002', marcar(sessions.vend3.client, 'juan'), ['P0002'], FUERA);
  await expectExpectedFailure('potencial sup2 → lead de sup1 (juan) → P0002', marcar(sessions.sup2.client, 'juan'), ['P0002'], FUERA);
  await expectExpectedFailure('potencial sup1Nested → lead de su jefe (juan) → P0002', marcar(sessions.sup1Nested.client, 'juan'), ['P0002'], FUERA);
  await expectExpectedFailure('potencial vend1 → lead inexistente → P0002', marcarId(sessions.vend1.client, randomUUID()), ['P0002'], FUERA);
  // Roles que nunca marcan: 42501 (antes de tocar el lead).
  for (const clave of ['gerencia', 'coordinador', 'directorio', 'vendInactive']) {
    await expectExpectedFailure(`potencial ${clave} → juan → 42501`, marcar(sessions[clave].client, 'juan'), ['42501'], ROL);
  }
  await expectExpectedFailure('potencial vendInactive → su propio lead (inactiveOwned) → 42501: la baja revoca la marca',
    marcar(sessions.vendInactive.client, 'inactiveOwned'), ['42501'], ROL);
  // Argumentos: nivel fuera del enum.
  await expectExpectedFailure('potencial vend1 nivel inválido → 22P02', marcar(sessions.vend1.client, 'juan', 'dorado'), ['22P02'], /invalid input value for enum|valor de entrada no v[aá]lido/i);
  // Sin EXECUTE para anon ni service_role.
  const anon = createClient(SUPABASE_URL, ANON_KEY, clientOptions('crm-rls-anon-potencial'));
  await expectExpectedFailure('potencial anon → 42501 (sin EXECUTE)', marcar(anon, 'juan'), ['42501'], DENEGADO);
  await expectExpectedFailure('potencial service_role → 42501 (sin EXECUTE)', marcar(admin, 'juan'), ['42501'], DENEGADO);
  // Tablas: sin grants para la API (regla de 4 capas: la pantalla leerá por una puerta, fase 3).
  for (const [clave, cliente] of [['vend1', sessions.vend1.client], ['gerencia', sessions.gerencia.client], ['anon', anon]]) {
    await expectExpectedFailure(`potencial ${clave} no lee crm.lead_potencial (sin grants)`,
      cliente.schema('crm').from('lead_potencial').select('lead_id').limit(1), ['42501'], DENEGADO);
    await expectExpectedFailure(`potencial ${clave} no lee crm.lead_potencial_eventos (sin grants)`,
      cliente.schema('crm').from('lead_potencial_eventos').select('lead_id').limit(1), ['42501'], DENEGADO);
  }
  await expectExpectedFailure('potencial vend1 INSERT directo en crm.lead_potencial → 42501',
    sessions.vend1.client.schema('crm').from('lead_potencial').insert({ lead_id: idDe('juan'), nivel: 'estrella', origen: 'manual', marcado_por: seed.profileIdByKey.vend1, marcado_en: new Date().toISOString() }),
    ['42501'], DENEGADO);
  await expectExpectedFailure('potencial gerencia UPDATE directo en crm.lead_potencial → 42501',
    sessions.gerencia.client.schema('crm').from('lead_potencial').update({ nivel: 'frio' }).eq('lead_id', idDe('juan')),
    ['42501'], DENEGADO);
  await expectExpectedFailure('potencial vend1 INSERT directo en crm.lead_potencial_eventos → 42501',
    sessions.vend1.client.schema('crm').from('lead_potencial_eventos').insert({ lead_id: idDe('juan'), nivel_nuevo: 'estrella', motivo: 'manual', por: seed.profileIdByKey.vend1 }),
    ['42501'], DENEGADO);
}


```
