Reading prompt from stdin...
OpenAI Codex v0.159.0
--------
workdir: /Users/usuario/Desktop/DESARROLLO/DESARROLLO/wt-potencial-lead
model: gpt-6-astra
provider: openai
approval: never
sandbox: read-only
reasoning effort: xhigh
reasoning summaries: none
session id: 01a0f46b-7dcc-7ad1-be33-867fc2123e65
--------
user
ROLE: SECONDARY_REVIEWER.
Do not modify files. Do not implement the task. Do not invoke Claude. Do not delegate to another coding agent. Do not create another review chain.

# Encargo de revisión — RONDA 1 (LEVEL 3: tablas nuevas, permisos, puerta SECURITY DEFINER)

Eres el revisor secundario. Sin base de datos ni red: todo está transcrito abajo. Responde con VERDICT (APPROVE / CHANGES_REQUESTED), SUMMARY, FINDINGS P0–P3 con evidencia (archivo/línea/fragmento), riesgos y test gaps, NEXT ACTIONS y CONFIDENCE. Sin hallazgo sin evidencia; distingue hipótesis. Tu tarea: REFUTAR.

## Qué se pide (negocio)
Los analistas del CRM marcan cada lead como frío, tibio o estrella. Reglas del dueño (Miguel, 30/09): marcan el analista dueño del lead y su supervisor; gerencia solo ve y filtra; no hay tope; la marca es del lead (viaja al reasignar); no cambia el orden de la cola; marcar NO es una gestión. Esta migración es la FASE 1 (solo servidor, apagada por bandera). Fase 2 (después): tarea diaria que baja Estrella→Tibio a los 5 días sin gestión y Tibio→Frío a los 10. Fase 3: pantalla y encender la bandera.

## Decisiones de diseño a refutar
1. Tabla propia (`crm.lead_potencial` + historial `crm.lead_potencial_eventos`) en vez de columnas en `crm.leads`, porque todo UPDATE de leads reescribe `actualizado_en` (llave de orden de la cartera, índice `leads_orden_cartera_idx (actualizado_en desc, id)`) y dispara ~20 triggers (SLA, tenencia, identidad).
2. Puerta SECURITY DEFINER que verifica rol y ámbito explícitamente (en vez de INVOKER + policy `leads_update`, que deja pasar a gerencia).
3. Ámbito: vendedor → solo su lead (`vendedor_ids_visibles` le devuelve él mismo); supervisor → su subárbol, y el lead parqueado (vendedor_id null) en `asignado_supervisor_id` de su subárbol. Cerrados (convertido/descartado) → 22023. Orden de validación: sesión → args → rol → ámbito → etapa → bandera → escritura.
4. RLS de lectura con `exists (select 1 from crm.leads l where l.id = lead_id)` (la RLS de leads del consultante decide).
5. Historial inmutable por trigger (UPDATE/DELETE/TRUNCATE → P0409); columna `orden` identity para orden total (creado_en empata dentro de una transacción).
6. Preflight fija identidad de `private.rol_crm` y `private.vendedor_ids_visibles` con md5(prosrc|prosecdef|provolatile|proconfig) porque `pg_get_functiondef` cambia con el search_path de la sesión (medido: 6 funciones de postventa renderizan `DEFAULT uid()` vs `DEFAULT auth.uid()`).
7. Sin `negocio_id` (ninguna tabla del esquema crm lo tiene).

## Preguntas concretas
a. ¿Hay algún camino por el que gerencia, coordinador, directorio o un analista ajeno escriba una marca, o por el que la RLS de lectura filtre de más o de menos?
b. ¿`private.potencial_rechazo` puede devolver NULL (= permitido) indebidamente? (guardas con `is not true`).
c. ¿El candado `pg_advisory_xact_lock(hashtext('crm.lead_potencial'), hashtext(lead_id::text))` + upsert es correcto ante marcas simultáneas? ¿Colisión con otro candado de la casa?
d. ¿Postflight/preflight con falsos verdes (NULL, ACL heredada de PUBLIC, `search_path=""` con comillas)?
e. ¿Falta algo que la fase 2 (caducidad) o la fase 3 (lectura en listados) vaya a necesitar y conviene poner ya (índices, columnas)?
f. Error 55000 con la bandera apagada DESPUÉS de autorizar: ¿filtra información o es aceptable?

## Evidencia de ejecución (banco Docker propio, esquema de prod del 30/09 con paridad de huellas 280 crm + 540 private)
- Migración PASS (notice del postflight); repetida → PREFLIGHT «ya aplicada»; reversa PASS; reversa repetida → se niega; migración de nuevo PASS.
- Prueba sintética (abajo, deshecha): 63 de 63 OK.
- Mutantes de la migración, todos rechazados: privada sin revoke (POSTFLIGHT privadas), `grant select, insert` (POSTFLIGHT grants), sin trigger TRUNCATE (POSTFLIGHT disparadores), puerta INVOKER (POSTFLIGHT puerta), bandera encendida (POSTFLIGHT bandera), `private.rol_crm` alterado antes (PREFLIGHT huellas).
- Mutantes de lógica cazados por la sintética: gerencia pasa (7 fallas), cerrado pasa (3), parqueo abierto (1).
- Registrador idempotente; con contenido ajeno se niega. Verificador solo lectura OK.
- `auth.uid()` de PRODUCCIÓN (leído 30/09): `coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'))::uuid`. El del banco solo lee `claim.sub`; la sintética fija ambos.
- `check:scripts` PASS; `test:rls:preflight` NOT RUN (exige credenciales).

## Contexto vivo de producción (transcrito del volcado del 30/09)

### private.rol_crm
```sql
CREATE OR REPLACE FUNCTION "private"."rol_crm"("p_perfil_id" "uuid") RETURNS "text"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select e.rol_crm
  from crm.equipo e
  join public.perfiles p on p.id = e.perfil_id
  where e.perfil_id = p_perfil_id
    and e.activo is true and p.activo is true
    and e.rol_crm in (
      'vendedor','supervisor','gerencia','coordinador','directorio'
    )
    -- Directorio es una capacidad de lectura, no un alias operativo de
    -- Gerencia. Una pareja desalineada no recibe ningún rol efectivo.
    and (
      (p.rol = 'directorio' and e.rol_crm = 'directorio')
      or (p.rol is distinct from 'directorio' and e.rol_crm <> 'directorio')
    )
    -- Superadmin Portal gobierna roles CRM; solo una membresía de Gerencia le
    -- suma autoridad operativa. Cualquier otro rol queda fuera del gate global.
    and (p.rol is distinct from 'superadmin' or e.rol_crm = 'gerencia');
$$;
```
### private.vendedor_ids_visibles
```sql
CREATE OR REPLACE FUNCTION "private"."vendedor_ids_visibles"("p_perfil_id" "uuid") RETURNS SETOF "uuid"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_rol text;
begin
  if p_perfil_id is distinct from (select auth.uid())
     and not private.es_lector_global() then
    return; -- defensa en profundidad: no enumerar equipos ajenos
  end if;

  v_rol := private.rol_crm(p_perfil_id);

  if v_rol is null then
    return;
  elsif v_rol = 'gerencia' then
    return query select e.perfil_id from crm.equipo e; -- incluye históricos
  elsif v_rol = 'supervisor' then
    return query
      with recursive subarbol as (
        select e.perfil_id
        from crm.equipo e
        where e.perfil_id = p_perfil_id
        union -- corta ciclos accidentales A↔B
        select e.perfil_id
        from crm.equipo e
        join subarbol s on e.supervisor_id = s.perfil_id
      )
      select s.perfil_id from subarbol s;
  elsif v_rol = 'vendedor' then
    return next p_perfil_id;
  else
    return; -- coordinador/rol futuro: deny-by-default
  end if;
end;
$$;
```
### private.es_lector_global
```sql
CREATE OR REPLACE FUNCTION "private"."es_lector_global"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  with actor as materialized (
    select (select auth.uid()) as uid
  )
  select coalesce(private.rol_crm(a.uid) = 'directorio', false)
    or exists (
      select 1
      from public.perfiles p
      where p.id = a.uid
        and p.activo is true
        and p.rol = 'directorio'
        -- El fallback histórico solo aplica sin membresía. Una fila CRM
        -- inactiva o desalineada es revocación, nunca una segunda puerta.
        and not exists (
          select 1 from crm.equipo e where e.perfil_id = p.id
        )
    )
  from actor a;
$$;
```
### Policies de crm.leads
```sql
CREATE POLICY "leads_select" ON "crm"."leads" FOR SELECT TO "authenticated" USING ((("activo" = true) AND (("vendedor_id" IN ( SELECT "private"."vendedor_ids_visibles"(( SELECT "auth"."uid"() AS "uid")) AS "vendedor_ids_visibles")) OR (("vendedor_id" IS NULL) AND ("asignado_supervisor_id" IN ( SELECT "private"."vendedor_ids_visibles"(( SELECT "auth"."uid"() AS "uid")) AS "vendedor_ids_visibles"))) OR (( SELECT "private"."rol_crm"(( SELECT "auth"."uid"() AS "uid")) AS "rol_crm") = 'gerencia'::"text") OR ( SELECT "private"."es_lector_global"() AS "es_lector_global"))));
CREATE POLICY "leads_update" ON "crm"."leads" FOR UPDATE TO "authenticated" USING ((("activo" = true) AND (("private"."rol_crm"(( SELECT "auth"."uid"() AS "uid")) = 'gerencia'::"text") OR ("vendedor_id" IN ( SELECT "private"."vendedor_ids_visibles"(( SELECT "auth"."uid"() AS "uid")) AS "vendedor_ids_visibles")) OR (("vendedor_id" IS NULL) AND ("asignado_supervisor_id" IN ( SELECT "private"."vendedor_ids_visibles"(( SELECT "auth"."uid"() AS "uid")) AS "vendedor_ids_visibles")))))) WITH CHECK (((("vendedor_id" IS NULL) OR ("vendedor_id" IN ( SELECT "private"."vendedor_ids_visibles"(( SELECT "auth"."uid"() AS "uid")) AS "vendedor_ids_visibles"))) AND (("asignado_supervisor_id" IS NULL) OR ("asignado_supervisor_id" IN ( SELECT "private"."vendedor_ids_visibles"(( SELECT "auth"."uid"() AS "uid")) AS "vendedor_ids_visibles"))) AND (("activo" = true) OR ("private"."rol_crm"(( SELECT "auth"."uid"() AS "uid")) = ANY (ARRAY['supervisor'::"text", 'gerencia'::"text"])))));
```
### private.leads_before_update (inicio)
```sql
CREATE OR REPLACE FUNCTION "private"."leads_before_update"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'crm', 'public'
    AS $$
declare
  v_priv boolean := coalesce(current_setting('crm.op_privilegiada', true) = 'on', false);
begin
  -- Columnas inmutables: restaurar siempre desde OLD.
  new.id := old.id;
  new.creado_por := old.creado_por;
  new.alta_manual := old.alta_manual;
  new.creado_en := old.creado_en;
  new.actualizado_en := now();

```
### crm.bandera_activa
```sql
CREATE OR REPLACE FUNCTION "crm"."bandera_activa"("p_nombre" "text") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select coalesce((select activo from crm.multiempresa_flags where nombre = p_nombre), false)
$$;
```
### private.set_actualizado_en_crm
```sql
CREATE OR REPLACE FUNCTION "private"."set_actualizado_en_crm"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'crm'
    AS $$
begin
  new.actualizado_en := now();
  return new;
end;
$$;
```
### Disparadores de crm.multiempresa_flags
```sql
CREATE OR REPLACE TRIGGER "trg_multiempresa_flags_00_serializa_puertas" BEFORE UPDATE OF "activo" ON "crm"."multiempresa_flags" FOR EACH ROW EXECUTE FUNCTION "private"."trg_multiempresa_flags_serializa_puertas"();
CREATE OR REPLACE TRIGGER "trg_multiempresa_flags_01_bloquear_piloto_f8" BEFORE INSERT OR UPDATE ON "crm"."multiempresa_flags" FOR EACH ROW EXECUTE FUNCTION "private"."trg_multiempresa_flags_bloquear_piloto_f8"();
CREATE OR REPLACE TRIGGER "trg_multiempresa_flags_touch" BEFORE UPDATE ON "crm"."multiempresa_flags" FOR EACH ROW EXECUTE FUNCTION "private"."set_actualizado_en_crm"();
CREATE OR REPLACE TRIGGER "trg_audit_multiempresa_flags" AFTER INSERT OR DELETE OR UPDATE ON "crm"."multiempresa_flags" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();
```
### private.log_audit_crm
```sql
CREATE OR REPLACE FUNCTION "private"."log_audit_crm"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_fila uuid;
  v_actor uuid;
  v_antes jsonb;
  v_despues jsonb;
begin
  begin
    v_fila := coalesce(
      (pg_catalog.to_jsonb(coalesce(new, old)) ->> 'id')::uuid,
      (pg_catalog.to_jsonb(coalesce(new, old)) ->> 'perfil_id')::uuid
    );
  exception when invalid_text_representation then
    v_fila := null;
  end;

  select p.id into v_actor
  from public.perfiles p where p.id = (select auth.uid());

  if tg_op in ('UPDATE', 'DELETE') then
    v_antes := pg_catalog.to_jsonb(old);
  end if;
  if tg_op in ('INSERT', 'UPDATE') then
    v_despues := pg_catalog.to_jsonb(new);
  end if;
  if tg_table_schema = 'crm' and tg_table_name = 'cuentas_bancarias' then
    v_antes := v_antes - array['numero_cuenta', 'cci', 'beneficiario_dni'];
    v_despues := v_despues - array['numero_cuenta', 'cci', 'beneficiario_dni'];
  end if;

  insert into public.audit_log
    (tabla, operacion, fila_id, usuario_id, data_antes, data_despues)
  values
    (tg_table_schema || '.' || tg_table_name, tg_op, v_fila, v_actor,
     v_antes, v_despues);
  return coalesce(new, old);
end;
$$;
```

## Archivos nuevos

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
--     del lead o su supervisor (su subárbol, incluido el lead parqueado en su bandeja).
--     Gerencia, Coordinación, Directorio y cualquier otro rol: 42501. Lead ajeno, inactivo o
--     inexistente: P0002 (no se distingue, para no revelar que existe). Lead convertido o
--     descartado: 22023. Volver a marcar el mismo nivel es válido: reinicia el reloj de la
--     caducidad (fase 2) y deja su evento.
--   · Bandera 'potencial_lead' en crm.multiempresa_flags, APAGADA: la puerta autoriza y
--     después se niega con 55000 hasta que la fase 3 (pantalla) la encienda.
--
-- CAPAS: puerta DEFINER (sesión, rol, ámbito, bandera; delega) → núcleo
--   private.potencial_marcar_nucleo (INVOKER: estado + evento, atómico) → tablas. El ámbito
--   lo decide private.potencial_rechazo (INVOKER, lee crm.leads). Los dos ayudantes privados
--   no tienen EXECUTE para ningún rol de la API.
-- SECURITY DEFINER, justificación: las tablas no dan INSERT/UPDATE a authenticated (una marca
--   no se escribe a mano por PostgREST) y la policy leads_update deja pasar a gerencia, que
--   aquí NO marca. La puerta verifica rol y ámbito de forma explícita con private.rol_crm y
--   private.vendedor_ids_visibles, los mismos ayudantes de leads_select/leads_update (el
--   preflight fija su identidad por md5 de cuerpo, DEFINER, volatilidad y configuración).
-- SIN negocio_id: ninguna tabla del esquema crm lo tiene (convención del CRM; la regla de 4
--   capas lo reconoce como deuda del CRM actual). Nombres de tiempo en español (creado_en).
-- LECTURA: SELECT para authenticated con RLS que refleja la visibilidad del lead
--   (exists sobre crm.leads, cuya propia RLS decide). anon y service_role: nada.
-- REVERSA: supabase/scripts/potencial-lead/reversa.sql (solo con las tablas vacías).

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
         or (n.nspname = 'private' and p.proname in ('potencial_rechazo', 'potencial_marcar_nucleo', 'potencial_evento_inmutable'))
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
  -- cuerpo + DEFINER + volatilidad + configuración: pg_get_functiondef no sirve aquí porque
  -- su texto cambia con el search_path de la sesión (medido en el banco el 30/09).
  select pg_catalog.md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|'
                        || coalesce(pg_catalog.array_to_string(p.proconfig, ','), ''))
    into v_md5_rol
  from pg_catalog.pg_proc p where p.oid = 'private.rol_crm(uuid)'::pg_catalog.regprocedure;
  select pg_catalog.md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|'
                        || coalesce(pg_catalog.array_to_string(p.proconfig, ','), ''))
    into v_md5_visibles
  from pg_catalog.pg_proc p where p.oid = 'private.vendedor_ids_visibles(uuid)'::pg_catalog.regprocedure;
  if (v_md5_rol = '76d693c51c4aa03637a4a553b1abea2f' and v_md5_visibles = '94054ec8431264cf68b55ddf463578f8') is not true then
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
'Nivel VIGENTE de potencial de cada lead (una fila por lead). Solo se escribe por crm.marcar_potencial_lead_fn (y, desde la fase 2, por la caducidad diaria). Tabla propia para no disparar los ~20 disparadores de crm.leads ni reordenar la cartera.';
comment on column crm.lead_potencial.id is 'Identificador de la fila.';
comment on column crm.lead_potencial.lead_id is 'Lead marcado. Único: la marca es del lead y viaja con él si se reasigna.';
comment on column crm.lead_potencial.nivel is 'Nivel vigente: frio, tibio o estrella.';
comment on column crm.lead_potencial.origen is 'Quién fijó el nivel vigente: manual (analista o supervisor) o caducidad (bajada automática por días sin gestión, fase 2).';
comment on column crm.lead_potencial.marcado_por is 'Perfil de la última persona que marcó el lead (no cambia con la caducidad).';
comment on column crm.lead_potencial.marcado_en is 'Última marca humana. Junto con la última gestión arranca el reloj de la caducidad.';
comment on column crm.lead_potencial.creado_en is 'Primera marca del lead.';
comment on column crm.lead_potencial.actualizado_en is 'Último cambio de la fila (marca o caducidad).';

comment on table crm.lead_potencial_eventos is
'Historial INMUTABLE de la marca de potencial: cada marca y cada bajada automática. Solo INSERT; UPDATE, DELETE y TRUNCATE se rechazan. No es una gestión: no vive en crm.actividades.';
comment on column crm.lead_potencial_eventos.id is 'Identificador del evento.';
comment on column crm.lead_potencial_eventos.orden is 'Orden total de inserción. creado_en empata dentro de una misma transacción; el historial se ordena por esta columna.';
comment on column crm.lead_potencial_eventos.lead_id is 'Lead al que pertenece el evento.';
comment on column crm.lead_potencial_eventos.nivel_anterior is 'Nivel antes del cambio; null en la primera marca.';
comment on column crm.lead_potencial_eventos.nivel_nuevo is 'Nivel después del cambio (igual al anterior si se volvió a confirmar).';
comment on column crm.lead_potencial_eventos.motivo is 'manual (una persona marcó) o caducidad (bajó sola por días sin gestión).';
comment on column crm.lead_potencial_eventos.por is 'Perfil que marcó; null solo cuando el motivo es caducidad (lo hizo el sistema).';
comment on column crm.lead_potencial_eventos.creado_en is 'Momento del cambio.';

-- ── 3 · RLS: lectura con la visibilidad del lead; sin escritura por la API ──────
create policy lead_potencial_select on crm.lead_potencial
  for select to authenticated
  using (exists (select 1 from crm.leads l where l.id = lead_potencial.lead_id));
comment on policy lead_potencial_select on crm.lead_potencial is
'Ve la marca quien ve el lead: el exists corre con la RLS de crm.leads del que consulta.';

create policy lead_potencial_eventos_select on crm.lead_potencial_eventos
  for select to authenticated
  using (exists (select 1 from crm.leads l where l.id = lead_potencial_eventos.lead_id));
comment on policy lead_potencial_eventos_select on crm.lead_potencial_eventos is
'Ve el historial quien ve el lead: el exists corre con la RLS de crm.leads del que consulta.';

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

  -- Mismo ámbito que las ramas no-gerencia de leads_update: el dueño, y si está parqueado
  -- (vendedor_id null), el supervisor de la bandeja. vendedor_ids_visibles devuelve al
  -- analista él mismo y al supervisor su subárbol.
  if (case
        when v_vendedor is not null then v_vendedor in (select private.vendedor_ids_visibles(p_actor))
        else v_supervisor in (select private.vendedor_ids_visibles(p_actor))
      end) is not true then
    return 'ambito';
  end if;

  if v_etapa in ('convertido', 'descartado') then
    return 'cerrado';
  end if;
  return null;
end;
$function$;
comment on function private.potencial_rechazo(uuid, uuid) is
'Decide si el actor puede marcar el potencial del lead: null = puede; rol | ambito | cerrado = motivo del rechazo. Solo vendedor (su lead) o supervisor (su subárbol y su parqueo). Sin EXECUTE para la API.';

create function private.potencial_marcar_nucleo(p_actor uuid, p_lead_id uuid, p_nivel crm.nivel_potencial)
returns crm.lead_potencial
language plpgsql
volatile
security invoker
set search_path = ''
as $function$
declare
  v_anterior crm.nivel_potencial;
  v_fila crm.lead_potencial;
begin
  -- Serializa marcas simultáneas del mismo lead: el evento guarda el nivel anterior real.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.lead_potencial'), pg_catalog.hashtext(p_lead_id::text));

  select p.nivel into v_anterior from crm.lead_potencial p where p.lead_id = p_lead_id;

  insert into crm.lead_potencial as p (lead_id, nivel, origen, marcado_por, marcado_en)
  values (p_lead_id, p_nivel, 'manual', p_actor, pg_catalog.now())
  on conflict (lead_id) do update
    set nivel = excluded.nivel,
        origen = 'manual',
        marcado_por = excluded.marcado_por,
        marcado_en = excluded.marcado_en
  returning p.* into v_fila;

  insert into crm.lead_potencial_eventos (lead_id, nivel_anterior, nivel_nuevo, motivo, por)
  values (p_lead_id, v_anterior, p_nivel, 'manual', p_actor);

  return v_fila;
end;
$function$;
comment on function private.potencial_marcar_nucleo(uuid, uuid, crm.nivel_potencial) is
'Operación atómica de marcar: fija el nivel vigente (origen manual, reinicia marcado_en) y deja su evento inmutable. No autoriza: eso lo hace la puerta. Sin EXECUTE para la API.';

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

  v_rechazo := private.potencial_rechazo(v_actor, p_lead_id);
  if v_rechazo = 'rol' then
    raise exception 'Solo el analista del lead o su supervisor pueden marcar su potencial' using errcode = '42501';
  elsif v_rechazo = 'ambito' then
    raise exception 'Lead no encontrado o fuera de tu ámbito' using errcode = 'P0002';
  elsif v_rechazo = 'cerrado' then
    raise exception 'Un lead convertido o descartado no lleva marca de potencial' using errcode = '22023';
  elsif v_rechazo is not null then
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
'Puerta: marca el potencial (frio, tibio, estrella) de un lead. Solo el analista dueño o su supervisor; gerencia y demás roles 42501; lead ajeno P0002; cerrado 22023; bandera potencial_lead apagada 55000. Devuelve {lead_id, nivel, origen, marcado_por, marcado_en}.';

-- ── 7 · Bandera (apagada hasta la fase 3) ──────────────────────────────────────
insert into crm.multiempresa_flags (nombre, activo, descripcion)
values ('potencial_lead', false, 'Marca de potencial del lead (Frío, Tibio, Estrella): la puerta crm.marcar_potencial_lead_fn solo escribe con la bandera encendida')
on conflict (nombre) do nothing;

-- ── 8 · Permisos ───────────────────────────────────────────────────────────────
alter function private.potencial_evento_inmutable() owner to postgres;
alter function private.potencial_rechazo(uuid, uuid) owner to postgres;
alter function private.potencial_marcar_nucleo(uuid, uuid, crm.nivel_potencial) owner to postgres;
alter function crm.marcar_potencial_lead_fn(uuid, crm.nivel_potencial) owner to postgres;

revoke all on crm.lead_potencial, crm.lead_potencial_eventos from public, anon, authenticated, service_role;
revoke all on sequence crm.lead_potencial_eventos_orden_seq from public, anon, authenticated, service_role;
grant select on crm.lead_potencial, crm.lead_potencial_eventos to authenticated;

revoke all on function private.potencial_evento_inmutable() from public, anon, authenticated, service_role;
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
    'private.potencial_rechazo(uuid,uuid)'::pg_catalog.regprocedure,
    'private.potencial_marcar_nucleo(uuid,uuid,crm.nivel_potencial)'::pg_catalog.regprocedure
  ];
  v_disparadores text;
begin
  -- Puerta: DEFINER, dueño postgres, search_path vacío, lock_timeout, EXECUTE solo authenticated.
  if (
    exists (
      select 1 from pg_catalog.pg_proc p
      where p.oid = v_puerta and p.prosecdef and p.proowner = 'postgres'::pg_catalog.regrole
        and p.proconfig is not null
        and p.proconfig @> array['search_path=""', 'lock_timeout=5s']::text[]
        and p.proacl is not null
    )
    and not exists (select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
                    where p.oid = v_puerta and a.privilege_type = 'EXECUTE'
                      and a.grantee not in ('postgres'::pg_catalog.regrole, 'authenticated'::pg_catalog.regrole))
    and exists (select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
                where p.oid = v_puerta and a.privilege_type = 'EXECUTE' and a.grantee = 'authenticated'::pg_catalog.regrole)
  ) is not true then
    raise exception 'POSTFLIGHT potencial_lead: la puerta no quedó DEFINER/postgres/search_path vacío/EXECUTE solo authenticated';
  end if;

  -- Privadas: INVOKER, search_path vacío y ACL explícita sin nadie más que postgres.
  if (
    (select count(*) from pg_catalog.pg_proc p
      where p.oid = any (v_privadas) and not p.prosecdef and p.proowner = 'postgres'::pg_catalog.regrole
        and p.proconfig is not null and p.proconfig @> array['search_path=""']::text[]
        and p.proacl is not null) = 3
    and not exists (select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
                    where p.oid = any (v_privadas) and a.grantee <> 'postgres'::pg_catalog.regrole)
  ) is not true then
    raise exception 'POSTFLIGHT potencial_lead: los ayudantes privados no quedaron INVOKER/search_path vacío/sin EXECUTE para la API';
  end if;

  -- Tablas: RLS activa, una sola policy (SELECT) cada una, SELECT como único privilegio de la API.
  if (
    (select count(*) from pg_catalog.pg_class c
      where c.oid in ('crm.lead_potencial'::pg_catalog.regclass, 'crm.lead_potencial_eventos'::pg_catalog.regclass)
        and c.relrowsecurity) = 2
    and (select count(*) from pg_catalog.pg_policies pp
          where pp.schemaname = 'crm' and pp.tablename in ('lead_potencial', 'lead_potencial_eventos')) = 2
    and (select count(*) from pg_catalog.pg_policies pp
          where pp.schemaname = 'crm' and pp.tablename in ('lead_potencial', 'lead_potencial_eventos')
            and pp.cmd = 'SELECT' and pp.roles = array['authenticated']::name[]) = 2
    and not exists (
      select 1 from information_schema.role_table_grants g
      where g.table_schema = 'crm' and g.table_name in ('lead_potencial', 'lead_potencial_eventos')
        and (g.grantee in ('PUBLIC', 'anon', 'service_role')
             or (g.grantee = 'authenticated' and g.privilege_type <> 'SELECT'))
    )
    and (select count(*) from information_schema.role_table_grants g
          where g.table_schema = 'crm' and g.table_name in ('lead_potencial', 'lead_potencial_eventos')
            and g.grantee = 'authenticated' and g.privilege_type = 'SELECT') = 2
  ) is not true then
    raise exception 'POSTFLIGHT potencial_lead: RLS, policies o grants de las tablas no son los previstos';
  end if;

  -- Disparadores exactos del historial y de la tabla vigente, activos para sesiones normales.
  select string_agg(t.tgname || '[' || t.tgenabled::text || ']', ',' order by t.tgname)
    into v_disparadores
  from pg_catalog.pg_trigger t
  where t.tgrelid in ('crm.lead_potencial'::pg_catalog.regclass, 'crm.lead_potencial_eventos'::pg_catalog.regclass)
    and not t.tgisinternal;
  if (v_disparadores = 'lead_potencial_evento_inmutable[O],lead_potencial_evento_no_truncate[O],'
                       || 'trg_audit_lead_potencial[O],trg_audit_lead_potencial_eventos[O],trg_lead_potencial_touch[O]') is not true then
    raise exception 'POSTFLIGHT potencial_lead: disparadores inesperados: %', coalesce(v_disparadores, '(ninguno)');
  end if;

  -- Bandera creada y apagada.
  if (select f.activo from crm.multiempresa_flags f where f.nombre = 'potencial_lead') is distinct from false then
    raise exception 'POSTFLIGHT potencial_lead: la bandera potencial_lead no quedó creada y apagada';
  end if;

  raise notice 'potencial_lead OK: tipo, 2 tablas (RLS solo lectura), núcleo INVOKER, puerta DEFINER solo authenticated, bandera apagada.';
end;
$postflight$;

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
insert into lds (k) values ('L1'), ('L1n'), ('L2'), ('LP'), ('LC'), ('LD'), ('LI'), ('NADA');
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
  (pg_temp.l('LI'),  'POTENCIAL LI',  '+51987650007', 'landing', 20000, 'PEN', 'contactado', pg_temp.a('V1'),  null, false, null);
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
  select count(*) into n from crm.lead_potencial where lead_id = p_lead;
  select count(*) into m from crm.lead_potencial_eventos where lead_id = p_lead;
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
  v_actualizado_antes timestamptz;
  v_actividades_antes int;
  v_marcado_en timestamptz;
  v_n int;
begin
  -- ── Catálogo: ayudantes privados sin EXECUTE para la API; puerta solo authenticated ──
  perform pg_temp.esperar('privadas sin EXECUTE de anon/authenticated/service_role/PUBLIC', '0', (
    select count(*)::text from pg_proc p, aclexplode(p.proacl) x
    where p.oid in ('private.potencial_rechazo(uuid,uuid)'::regprocedure,
                    'private.potencial_marcar_nucleo(uuid,uuid,crm.nivel_potencial)'::regprocedure,
                    'private.potencial_evento_inmutable()'::regprocedure)
      and x.grantee <> 'postgres'::regrole));
  perform pg_temp.esperar('puerta: EXECUTE solo postgres y authenticated', 'authenticated,postgres', (
    select string_agg(x.grantee::regrole::text, ',' order by x.grantee::regrole::text)
    from pg_proc p, aclexplode(p.proacl) x
    where p.oid = 'crm.marcar_potencial_lead_fn(uuid,crm.nivel_potencial)'::regprocedure and x.privilege_type = 'EXECUTE'));
  perform pg_temp.esperar('bandera nace apagada', 'false', (select activo::text from crm.multiempresa_flags where nombre = 'potencial_lead'));

  -- ── Bandera APAGADA: quien pasa rol y ámbito recibe 55000; los demás, su rechazo ──
  perform pg_temp.esperar('sin sesión', '42501', pg_temp.marcar(null, pg_temp.l('L1'), 'estrella'));
  perform pg_temp.esperar('V1 sin lead (null)', '22023', pg_temp.marcar(pg_temp.a('V1'), null, 'estrella'));
  perform pg_temp.esperar('V1 → su lead L1 (pasa, bandera apagada)', '55000', pg_temp.marcar(pg_temp.a('V1'), pg_temp.l('L1'), 'estrella'));
  perform pg_temp.esperar('V1 → L2 de otro equipo', 'P0002', pg_temp.marcar(pg_temp.a('V1'), pg_temp.l('L2'), 'estrella'));
  perform pg_temp.esperar('V1 → LP parqueado en su supervisor', 'P0002', pg_temp.marcar(pg_temp.a('V1'), pg_temp.l('LP'), 'estrella'));
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
  select l.actualizado_en into v_actualizado_antes from crm.leads l where l.id = pg_temp.l('L1');
  select count(*) into v_actividades_antes from crm.actividades a where a.lead_id = pg_temp.l('L1');

  perform pg_temp.esperar('V1 marca L1 estrella', 'ok:estrella', pg_temp.marcar(pg_temp.a('V1'), pg_temp.l('L1'), 'estrella'));
  perform pg_temp.esperar('primer evento: null → estrella por V1', 'null>estrella/manual/V1', (
    select coalesce(e.nivel_anterior::text, 'null') || '>' || e.nivel_nuevo || '/' || e.motivo || '/' || (select k from act where id = e.por)
    from crm.lead_potencial_eventos e where e.lead_id = pg_temp.l('L1') order by e.orden limit 1));
  select p.marcado_en into v_marcado_en from crm.lead_potencial p where p.lead_id = pg_temp.l('L1');

  perform pg_temp.esperar('V1 cambia L1 a tibio', 'ok:tibio', pg_temp.marcar(pg_temp.a('V1'), pg_temp.l('L1'), 'tibio'));
  perform pg_temp.esperar('S1 (su supervisor) vuelve L1 a estrella', 'ok:estrella', pg_temp.marcar(pg_temp.a('S1'), pg_temp.l('L1'), 'estrella'));
  perform pg_temp.esperar('S1 reconfirma estrella (mismo nivel)', 'ok:estrella', pg_temp.marcar(pg_temp.a('S1'), pg_temp.l('L1'), 'estrella'));
  perform pg_temp.esperar('estado vigente de L1: una fila, estrella, manual, por S1', '1|estrella|manual|S1', (
    select count(*) || '|' || max(p.nivel::text) || '|' || max(p.origen) || '|' || max((select k from act where id = p.marcado_por))
    from crm.lead_potencial p where p.lead_id = pg_temp.l('L1')));
  perform pg_temp.esperar('historial de L1 en orden', 'null>estrella,estrella>tibio,tibio>estrella,estrella>estrella', (
    select string_agg(coalesce(e.nivel_anterior::text, 'null') || '>' || e.nivel_nuevo, ',' order by e.orden)
    from crm.lead_potencial_eventos e where e.lead_id = pg_temp.l('L1')));
  -- En una sola transacción now() no avanza: marcado_en se reescribe con el mismo instante.
  perform pg_temp.esperar('marcado_en se reescribe en cada marca', 'true', (
    select (p.marcado_en >= v_marcado_en)::text from crm.lead_potencial p where p.lead_id = pg_temp.l('L1')));
  perform pg_temp.esperar('marcar NO toca crm.leads.actualizado_en (no reordena la cartera)', 'true', (
    select (l.actualizado_en = v_actualizado_antes)::text from crm.leads l where l.id = pg_temp.l('L1')));
  perform pg_temp.esperar('marcar NO crea actividades (no es gestión)', v_actividades_antes::text, (
    select count(*)::text from crm.actividades a where a.lead_id = pg_temp.l('L1')));

  perform pg_temp.esperar('S1 marca LP parqueado', 'ok:frio', pg_temp.marcar(pg_temp.a('S1'), pg_temp.l('LP'), 'frio'));
  perform pg_temp.esperar('V1 sigue sin poder con L2', 'P0002', pg_temp.marcar(pg_temp.a('V1'), pg_temp.l('L2'), 'estrella'));
  perform pg_temp.esperar('gerencia sigue sin marcar', '42501', pg_temp.marcar(pg_temp.a('G'), pg_temp.l('L1'), 'frio'));
  perform pg_temp.esperar('V1 sigue sin marcar un convertido', '22023', pg_temp.marcar(pg_temp.a('V1'), pg_temp.l('LC'), 'estrella'));

  -- ── Lectura (RLS): ve la marca quien ve el lead ──
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

### supabase/scripts/potencial-lead/reversa.sql
```sql
-- REVERSA de 20260930213647_crm_potencial_lead.
-- Solo mientras la función no se usó: se niega si hay una sola marca o evento, o si la bandera
-- está encendida (regla de la casa: en producción no se borra lo que tiene datos; con datos se
-- CIERRA con la bandera y se observa). Conserva la fila de schema_migrations: anotar la reversa
-- en MIGRACIONES.md.
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
  if (
    (select count(*) from crm.lead_potencial) = 0
    and (select count(*) from crm.lead_potencial_eventos) = 0
    and coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'potencial_lead'), false) = false
  ) is not true then
    raise exception 'REVERSA potencial_lead: hay marcas, eventos o la bandera está encendida; apaga la bandera y no borres datos';
  end if;
end;
$chk$;

drop function crm.marcar_potencial_lead_fn(uuid, crm.nivel_potencial);
drop function private.potencial_marcar_nucleo(uuid, uuid, crm.nivel_potencial);
drop function private.potencial_rechazo(uuid, uuid);
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
                       or (n.nspname = 'private' and p.proname in ('potencial_rechazo', 'potencial_marcar_nucleo', 'potencial_evento_inmutable')))
    and not exists (select 1 from crm.multiempresa_flags f where f.nombre = 'potencial_lead')
  ) is not true then
    raise exception 'REVERSA potencial_lead: quedaron objetos';
  end if;
  raise notice 'REVERSA potencial_lead OK: sin objetos ni bandera.';
end;
$post$;
commit;

```

### supabase/scripts/test-rls.mjs — bloque nuevo (API, sin escribir)
```js
// ── Potencial del lead (20260930213647): puerta crm.marcar_potencial_lead_fn ──────────────────
// Solo rechazos: con la bandera 'potencial_lead' APAGADA (así nace) nadie escribe. Quien pasa rol y
// ámbito recibe 55000 «todavía no está activada»: ese rechazo ES el positivo sin escribir (la puerta
// valida sesión → rol → ámbito → etapa y solo después mira la bandera). Las escrituras, el historial
// inmutable, la reasignación y que marcar no toca crm.leads ni crm.actividades los prueba
// supabase/scripts/potencial-lead/prueba-sintetica.sql (63 casos) en un banco, deshecho.
// Salto RUIDOSO si la puerta no está en esta base; con CRM_RLS_EXIGE_POTENCIAL=1 es un FALLO.
async function testPotencialLead(sessions, seed) {
  console.log('\n— Potencial del lead: puerta de la marca (rechazos, sin escribir) —');
  const FN = 'marcar_potencial_lead_fn';
  const lead = (key) => seed.leadByName.get(LEAD_BY_KEY[key].name)?.id;
  const marcar = (cliente, key, nivel = 'estrella') =>
    cliente.schema('crm').rpc(FN, { p_lead_id: typeof key === 'string' ? lead(key) : key, p_nivel: nivel });
  {
    const sonda = await marcar(sessions.vend1.client, 'juan');
    if (sonda.error?.code === 'PGRST202') {
      const msg = `⚠ crm.${FN} NO desplegada en esta base: bloque de Potencial del lead SALTADO (no probado)`;
      if (process.env.CRM_RLS_EXIGE_POTENCIAL === '1') fail(msg);
      else console.log(`  ${msg}`);
      return;
    }
  }
  const APAGADA = /todav[ií]a no est[aá] activada/i;
  const FUERA = /no encontrado o fuera de tu [aá]mbito/i;
  const ROL = /solo el analista del lead o su supervisor/i;

  // Pasan rol y ámbito → mueren en la bandera (el positivo sin escribir).
  await expectExpectedFailure('potencial vend1 → su lead (juan) llega a la bandera', marcar(sessions.vend1.client, 'juan'), ['55000'], APAGADA);
  await expectExpectedFailure('potencial sup1 → lead de su analista (juan) llega a la bandera', marcar(sessions.sup1.client, 'juan'), ['55000'], APAGADA);
  await expectExpectedFailure('potencial sup1 → lead de su subárbol (carlos) llega a la bandera', marcar(sessions.sup1.client, 'carlos'), ['55000'], APAGADA);
  await expectExpectedFailure('potencial sup1 → lead parqueado en su bandeja (luis) llega a la bandera', marcar(sessions.sup1.client, 'luis'), ['55000'], APAGADA);
  // Fuera de ámbito: P0002 (no revela si el lead existe).
  await expectExpectedFailure('potencial vend1 → lead de otro equipo (ana) → P0002', marcar(sessions.vend1.client, 'ana'), ['P0002'], FUERA);
  await expectExpectedFailure('potencial vend1 → lead parqueado (luis) → P0002', marcar(sessions.vend1.client, 'luis'), ['P0002'], FUERA);
  await expectExpectedFailure('potencial vend3 → lead de vend1 (juan) → P0002', marcar(sessions.vend3.client, 'juan'), ['P0002'], FUERA);
  await expectExpectedFailure('potencial sup2 → lead de sup1 (juan) → P0002', marcar(sessions.sup2.client, 'juan'), ['P0002'], FUERA);
  await expectExpectedFailure('potencial sup1Nested → lead de su jefe (juan) → P0002', marcar(sessions.sup1Nested.client, 'juan'), ['P0002'], FUERA);
  await expectExpectedFailure('potencial vend1 → lead inexistente → P0002', marcar(sessions.vend1.client, randomUUID()), ['P0002'], FUERA);
  // Roles que nunca marcan: 42501.
  for (const clave of ['gerencia', 'coordinador', 'directorio', 'vendInactive']) {
    await expectExpectedFailure(`potencial ${clave} → juan → 42501`, marcar(sessions[clave].client, 'juan'), ['42501'], ROL);
  }
  // Argumentos: nivel fuera del enum.
  await expectExpectedFailure('potencial vend1 nivel inválido → 22P02', marcar(sessions.vend1.client, 'juan', 'dorado'), ['22P02'], /invalid input value for enum|valor de entrada no v[aá]lido/i);
  // Sin EXECUTE para anon ni service_role.
  const anon = createClient(SUPABASE_URL, ANON_KEY, clientOptions('crm-rls-anon-potencial'));
  await expectExpectedFailure('potencial anon → 42501 (sin EXECUTE)', marcar(anon, 'juan'), ['42501'], /permission denied|denegado/i);
  await expectExpectedFailure('potencial service_role → 42501 (sin EXECUTE)', marcar(admin, 'juan'), ['42501'], /permission denied|denegado/i);
  // Tablas: authenticated solo lee (RLS); nadie escribe directo; anon no lee.
  const lectura = await sessions.vend1.client.schema('crm').from('lead_potencial').select('lead_id').limit(1);
  check(!lectura.error, 'potencial vend1 puede leer crm.lead_potencial (SELECT con RLS)', lectura.error ? errorText(lectura.error) : '');
  await expectExpectedFailure('potencial vend1 INSERT directo en crm.lead_potencial → 42501',
    sessions.vend1.client.schema('crm').from('lead_potencial').insert({ lead_id: lead('juan'), nivel: 'estrella', origen: 'manual', marcado_por: seed.profileIdByKey.vend1, marcado_en: new Date().toISOString() }),
    ['42501'], /permission denied|denegado/i);
  await expectExpectedFailure('potencial gerencia UPDATE directo en crm.lead_potencial → 42501',
    sessions.gerencia.client.schema('crm').from('lead_potencial').update({ nivel: 'frio' }).eq('lead_id', lead('juan')),
    ['42501'], /permission denied|denegado/i);
  await expectExpectedFailure('potencial vend1 INSERT directo en crm.lead_potencial_eventos → 42501',
    sessions.vend1.client.schema('crm').from('lead_potencial_eventos').insert({ lead_id: lead('juan'), nivel_nuevo: 'estrella', motivo: 'manual', por: seed.profileIdByKey.vend1 }),
    ['42501'], /permission denied|denegado/i);
  await expectExpectedFailure('potencial anon no lee crm.lead_potencial', anon.schema('crm').from('lead_potencial').select('lead_id').limit(1), ['42501'], /permission denied|denegado/i);
}


```


codex
Revisaré la evidencia transcrita, con foco en carreras de autorización, permisos efectivos y falsos positivos de las verificaciones. No modificaré archivos ni iniciaré otra revisión.

codex
Encontré tres problemas concretos: la autorización se comprueba antes de esperar el candado; la reversa comprueba que las tablas estén vacías sin bloquear escrituras concurrentes; y la prueba API trata el UUID inexistente como una clave del fixture y falla antes de llamar al servidor. También estoy contrastando qué garantizan realmente las comprobaciones del postflight.

codex
El postflight comprueba los nombres de los disparadores y el número de policies, pero no sus definiciones: algunos cambios que abren permisos pasarían ese control, aunque la prueba sintética sí los detectaría. También confirmé que la sonda API descrita como «sin escribir» guardaría una marca si la bandera estuviera encendida.

codex
**VERDICT: CHANGES_REQUESTED**

**SUMMARY**

La separación respecto de `crm.leads` está justificada y la autorización nominal deniega los roles indicados. Encontré dos carreras relevantes —autorización y reversa—, un fallo determinista en la prueba API y limitaciones concretas de las verificaciones. No demuestro un bypass directo de gerencia con el código transcrito.

Revisión exclusivamente estática: los resultados de ejecución son evidencia aportada, no pruebas ejecutadas por mí.

**FINDINGS P0–P3**

**F1 · P1 — La autorización puede quedar obsoleta antes de escribir.**

Evidencia: `20260930213647_crm_potencial_lead.sql`, funciones `potencial_rechazo`, `marcar_potencial_lead_fn` y `potencial_marcar_nucleo`:

```sql
-- La puerta autoriza primero:
v_rechazo := private.potencial_rechazo(v_actor, p_lead_id);

-- El núcleo adquiere el candado después:
perform pg_catalog.pg_advisory_xact_lock(...);
```

La lectura de `crm.leads` no bloquea la fila. Intercalación posible:

1. V1 pasa autorización para L1 y espera el candado.
2. Otra transacción reasigna L1 a V2, lo desactiva o lo cierra y confirma.
3. V1 obtiene el candado y escribe sin volver a validar.

El candado serializa marcas, pero no las coordina con las transiciones del lead. La sintética solo comprueba reasignaciones secuenciales.

**Acción:** proteger la fila del lead contra modificaciones relevantes, por ejemplo mediante `FOR NO KEY UPDATE`, y efectuar la validación decisiva después de adquirir los bloqueos. Mantenerlos hasta terminar. Esa adquisición debe estar en una función `VOLATILE`; no basta añadirla al ayudante `STABLE`. La revocación concurrente de membresías requiere considerar también cómo se coordinan los cambios de equipo.

**F2 · P1 — La reversa puede borrar escrituras que confirmen después de comprobar el vacío.**

Evidencia: `reversa.sql`, bloque `$chk$`:

```sql
(select count(*) from crm.lead_potencial) = 0
and (select count(*) from crm.lead_potencial_eventos) = 0
```

Después ejecuta `DROP TABLE`, sin bloquear previamente ambas tablas.

Intercalación posible: una marca autorizada con la bandera encendida deja filas todavía sin confirmar; otra transacción apaga la bandera. La reversa ve cero filas y bandera apagada. Su `DROP TABLE` espera al escritor; este confirma y, entonces, el `DROP` continúa y elimina los datos confirmados. El postflight de reversa puede aprobar. `lock_timeout = '5s'` no evita el caso si la espera dura menos.

**Acción:** adquirir bloqueos exclusivos sobre ambas tablas, en orden consistente, **antes de comprobar el vacío**, comprobarlo con una lectura actualizada y conservar los bloqueos hasta `COMMIT`. Coordinar también la bandera durante la reversa.

**F3 · P2 — La prueba del UUID inexistente falla en JavaScript antes del RPC.**

Evidencia: `test-rls.mjs`, `testPotencialLead`:

```js
const lead = (key) => seed.leadByName.get(LEAD_BY_KEY[key].name)?.id;
p_lead_id: typeof key === 'string' ? lead(key) : key
...
marcar(sessions.vend1.client, randomUUID())
```

`randomUUID()` devuelve un string. Por tanto, se busca como clave del fixture; `LEAD_BY_KEY[uuid]` es `undefined` y acceder a `.name` produce `TypeError`. No se comprueba el `P0002` y, sin recuperación exterior, tampoco se ejecutan los casos posteriores.

**Acción:** distinguir explícitamente claves de fixtures e identificadores UUID. El `check:scripts` reportado no acredita este comportamiento en ejecución.

**F4 · P2 — El bloque API «sin escribir» puede persistir marcas.**

Evidencia: la primera `sonda` llama a la puerta mutadora y solo trata `PGRST202`. Si la bandera está encendida, escribe y continúa. Las comprobaciones positivas posteriores vuelven a llamar a esa puerta.

No afirmo que esto haya ocurrido en el ensayo: es un comportamiento condicionado a ejecutar el bloque con la bandera encendida, escenario previsto para fase 3. Puede cambiar niveles, reiniciar `marcado_en` y añadir eventos antes de reportar fallos.

**Acción:** ejecutar estas pruebas mutadoras en un banco con rollback controlado, o declarar y garantizar otro contrato de ejecución. Para un verificador estrictamente de lectura, limitarse a consultas. Leer previamente la bandera reduce errores operativos, pero no proporciona una garantía transaccional de ausencia de escrituras.

**F5 · P2 — El postflight admite falsos verdes en las definiciones de policies y disparadores.**

Evidencia: el postflight comprueba `pp.cmd`, `pp.roles` y cantidades, pero no la expresión de la policy. Para disparadores agrega únicamente:

```sql
t.tgname || '[' || t.tgenabled::text || ']'
```

Dos mutantes concretos pasarían ese control:

- Sustituir el `USING (exists (...))` por `USING (true)`: cualquier `authenticated` leería esas filas.
- Cambiar el disparador inmutable de `BEFORE UPDATE OR DELETE` a `BEFORE UPDATE`, conservando nombre y estado: quedaría permitido borrar historial con privilegios suficientes.

La sintética aportada **sí detectaría estos mutantes**; el hallazgo afecta a la garantía del postflight por sí solo.

**Acción:** comprobar también la expresión de las policies y, para cada disparador, relación, función y eventos/momento mediante `tgrelid`, `tgfoid` y `tgtype`.

**Respuestas a las preguntas concretas**

- **a. Roles y lectura.** Sin concurrencia, la puerta rechaza gerencia, coordinación, directorio y actores sin rol efectivo. La lectura mediante `EXISTS` refleja correctamente la RLS de `crm.leads`: incluye su restricción de actividad y hace que el historial viaje con el lead. El camino demostrado para un analista que dejó de ser dueño es F1.

- **b. NULL permitido.** Las guardas de rol, existencia, actividad y ámbito fallan cerradas ante `NULL`. Hay dos condiciones que no puedo resolver con el esquema transcrito: `etapa IS NULL` no se rechaza, y un vendedor podría marcar un parqueado si `asignado_supervisor_id` apuntara a él, porque la rama de parqueo no exige `v_rol = 'supervisor'`. Son hipótesis condicionadas a que esos estados sean alcanzables; hacen falta los invariantes correspondientes o guardas explícitas.

- **c. Candado y upsert.** Para marcas concurrentes, bajo `READ COMMITTED` y con todos los escritores siguiendo el mismo protocolo, el candado protege la lectura del nivel anterior y el upsert. Las colisiones del hash entre leads añaden serialización y posibles timeouts; no mezclan filas. No se puede descartar una colisión con otros candados de dos enteros sin su inventario. El espacio de candados de un `bigint` es distinto. La fase 2 deberá respetar el mismo protocolo. `orden` permite ordenar los eventos, pero no representa el orden global de confirmación de transacciones.

- **d. Preflight/postflight.** Las guardas `IS NOT TRUE`, la comprobación de `proacl IS NOT NULL` y la bandera con `IS DISTINCT FROM false` evitan los falsos verdes por NULL señalados. `search_path=""` es la representación esperada en `proconfig`; no veo un fallo por esas comillas. En funciones, `aclexplode` permite detectar PUBLIC como grantee 0. Para tablas, el filtro por nombres de grantee no certifica todos los privilegios heredados: conviene comprobar ACL y permisos efectivos de los roles API. No hay evidencia aportada de una herencia peligrosa existente. La huella tampoco fija identidad completa: cambios de propietario, por ejemplo, no alteran el hash calculado.

- **e. Fases siguientes.** No identifico una columna imprescindible ausente. El estado conserva última marca humana y último cambio; el historial admite caducidad con autor nulo. El índice `(nivel, lead_id)` sirve para filtros; un índice temporal para caducidad debe decidirse con su consulta y volumen. La tarea necesitará una vía privilegiada propia, puesto que `service_role` está excluido. Además, conviene resolver una ambigüedad: negocio dice «sin gestión», mientras los comentarios permiten reiniciar el plazo mediante otra marca. La fase 1 todavía no ejecuta esa caducidad.

- **f. 55000 después de autorizar.** Es aceptable en el flujo nominal: solo revela la bandera respecto de un lead que el actor ya puede consultar. Ajeno, inexistente e inactivo conservan el mismo rechazo. No encuentro una filtración adicional por ese orden.

**Riesgos y test gaps**

- Faltan pruebas con dos sesiones para marcas simultáneas, reasignación/cierre concurrente y reversa frente a escrituras pendientes.
- `marcado_en >= v_marcado_en` pasa incluso si se elimina la actualización de `marcado_en`. Sembrar una fecha anterior permitiría verificar el reinicio. Conviene sembrar también `leads.actualizado_en` con una fecha distinta de `now()` para detectar cualquier actualización indebida.
- La comprobación de auditoría cuenta disparadores; no verifica filas de `audit_log`, actor ni valores registrados.
- La inmutabilidad se garantiza con disparadores habilitados en sesiones normales. No protege contra un administrador que deshabilite los disparadores.
- Migración, sintética y `check:scripts`: **PASS reportado**. `test:rls:preflight`: **NOT RUN reportado**. Ejecución independiente por este revisor: **NOT RUN**.

**NEXT ACTIONS**

Corregir F1–F4, reforzar el postflight según F5 y añadir pruebas concurrentes que reproduzcan las dos carreras. Después, ejecutar el bloque API corregido en un entorno que controle las escrituras y resolver los invariantes pendientes de parqueo y etapa.

**CONFIDENCE**

Alta en los defectos identificados por los fragmentos; limitada respecto de membresías heredadas, restricciones no transcritas y colisiones con candados existentes.
tokens used
44,082
**VERDICT: CHANGES_REQUESTED**

**SUMMARY**

La separación respecto de `crm.leads` está justificada y la autorización nominal deniega los roles indicados. Encontré dos carreras relevantes —autorización y reversa—, un fallo determinista en la prueba API y limitaciones concretas de las verificaciones. No demuestro un bypass directo de gerencia con el código transcrito.

Revisión exclusivamente estática: los resultados de ejecución son evidencia aportada, no pruebas ejecutadas por mí.

**FINDINGS P0–P3**

**F1 · P1 — La autorización puede quedar obsoleta antes de escribir.**

Evidencia: `20260930213647_crm_potencial_lead.sql`, funciones `potencial_rechazo`, `marcar_potencial_lead_fn` y `potencial_marcar_nucleo`:

```sql
-- La puerta autoriza primero:
v_rechazo := private.potencial_rechazo(v_actor, p_lead_id);

-- El núcleo adquiere el candado después:
perform pg_catalog.pg_advisory_xact_lock(...);
```

La lectura de `crm.leads` no bloquea la fila. Intercalación posible:

1. V1 pasa autorización para L1 y espera el candado.
2. Otra transacción reasigna L1 a V2, lo desactiva o lo cierra y confirma.
3. V1 obtiene el candado y escribe sin volver a validar.

El candado serializa marcas, pero no las coordina con las transiciones del lead. La sintética solo comprueba reasignaciones secuenciales.

**Acción:** proteger la fila del lead contra modificaciones relevantes, por ejemplo mediante `FOR NO KEY UPDATE`, y efectuar la validación decisiva después de adquirir los bloqueos. Mantenerlos hasta terminar. Esa adquisición debe estar en una función `VOLATILE`; no basta añadirla al ayudante `STABLE`. La revocación concurrente de membresías requiere considerar también cómo se coordinan los cambios de equipo.

**F2 · P1 — La reversa puede borrar escrituras que confirmen después de comprobar el vacío.**

Evidencia: `reversa.sql`, bloque `$chk$`:

```sql
(select count(*) from crm.lead_potencial) = 0
and (select count(*) from crm.lead_potencial_eventos) = 0
```

Después ejecuta `DROP TABLE`, sin bloquear previamente ambas tablas.

Intercalación posible: una marca autorizada con la bandera encendida deja filas todavía sin confirmar; otra transacción apaga la bandera. La reversa ve cero filas y bandera apagada. Su `DROP TABLE` espera al escritor; este confirma y, entonces, el `DROP` continúa y elimina los datos confirmados. El postflight de reversa puede aprobar. `lock_timeout = '5s'` no evita el caso si la espera dura menos.

**Acción:** adquirir bloqueos exclusivos sobre ambas tablas, en orden consistente, **antes de comprobar el vacío**, comprobarlo con una lectura actualizada y conservar los bloqueos hasta `COMMIT`. Coordinar también la bandera durante la reversa.

**F3 · P2 — La prueba del UUID inexistente falla en JavaScript antes del RPC.**

Evidencia: `test-rls.mjs`, `testPotencialLead`:

```js
const lead = (key) => seed.leadByName.get(LEAD_BY_KEY[key].name)?.id;
p_lead_id: typeof key === 'string' ? lead(key) : key
...
marcar(sessions.vend1.client, randomUUID())
```

`randomUUID()` devuelve un string. Por tanto, se busca como clave del fixture; `LEAD_BY_KEY[uuid]` es `undefined` y acceder a `.name` produce `TypeError`. No se comprueba el `P0002` y, sin recuperación exterior, tampoco se ejecutan los casos posteriores.

**Acción:** distinguir explícitamente claves de fixtures e identificadores UUID. El `check:scripts` reportado no acredita este comportamiento en ejecución.

**F4 · P2 — El bloque API «sin escribir» puede persistir marcas.**

Evidencia: la primera `sonda` llama a la puerta mutadora y solo trata `PGRST202`. Si la bandera está encendida, escribe y continúa. Las comprobaciones positivas posteriores vuelven a llamar a esa puerta.

No afirmo que esto haya ocurrido en el ensayo: es un comportamiento condicionado a ejecutar el bloque con la bandera encendida, escenario previsto para fase 3. Puede cambiar niveles, reiniciar `marcado_en` y añadir eventos antes de reportar fallos.

**Acción:** ejecutar estas pruebas mutadoras en un banco con rollback controlado, o declarar y garantizar otro contrato de ejecución. Para un verificador estrictamente de lectura, limitarse a consultas. Leer previamente la bandera reduce errores operativos, pero no proporciona una garantía transaccional de ausencia de escrituras.

**F5 · P2 — El postflight admite falsos verdes en las definiciones de policies y disparadores.**

Evidencia: el postflight comprueba `pp.cmd`, `pp.roles` y cantidades, pero no la expresión de la policy. Para disparadores agrega únicamente:

```sql
t.tgname || '[' || t.tgenabled::text || ']'
```

Dos mutantes concretos pasarían ese control:

- Sustituir el `USING (exists (...))` por `USING (true)`: cualquier `authenticated` leería esas filas.
- Cambiar el disparador inmutable de `BEFORE UPDATE OR DELETE` a `BEFORE UPDATE`, conservando nombre y estado: quedaría permitido borrar historial con privilegios suficientes.

La sintética aportada **sí detectaría estos mutantes**; el hallazgo afecta a la garantía del postflight por sí solo.

**Acción:** comprobar también la expresión de las policies y, para cada disparador, relación, función y eventos/momento mediante `tgrelid`, `tgfoid` y `tgtype`.

**Respuestas a las preguntas concretas**

- **a. Roles y lectura.** Sin concurrencia, la puerta rechaza gerencia, coordinación, directorio y actores sin rol efectivo. La lectura mediante `EXISTS` refleja correctamente la RLS de `crm.leads`: incluye su restricción de actividad y hace que el historial viaje con el lead. El camino demostrado para un analista que dejó de ser dueño es F1.

- **b. NULL permitido.** Las guardas de rol, existencia, actividad y ámbito fallan cerradas ante `NULL`. Hay dos condiciones que no puedo resolver con el esquema transcrito: `etapa IS NULL` no se rechaza, y un vendedor podría marcar un parqueado si `asignado_supervisor_id` apuntara a él, porque la rama de parqueo no exige `v_rol = 'supervisor'`. Son hipótesis condicionadas a que esos estados sean alcanzables; hacen falta los invariantes correspondientes o guardas explícitas.

- **c. Candado y upsert.** Para marcas concurrentes, bajo `READ COMMITTED` y con todos los escritores siguiendo el mismo protocolo, el candado protege la lectura del nivel anterior y el upsert. Las colisiones del hash entre leads añaden serialización y posibles timeouts; no mezclan filas. No se puede descartar una colisión con otros candados de dos enteros sin su inventario. El espacio de candados de un `bigint` es distinto. La fase 2 deberá respetar el mismo protocolo. `orden` permite ordenar los eventos, pero no representa el orden global de confirmación de transacciones.

- **d. Preflight/postflight.** Las guardas `IS NOT TRUE`, la comprobación de `proacl IS NOT NULL` y la bandera con `IS DISTINCT FROM false` evitan los falsos verdes por NULL señalados. `search_path=""` es la representación esperada en `proconfig`; no veo un fallo por esas comillas. En funciones, `aclexplode` permite detectar PUBLIC como grantee 0. Para tablas, el filtro por nombres de grantee no certifica todos los privilegios heredados: conviene comprobar ACL y permisos efectivos de los roles API. No hay evidencia aportada de una herencia peligrosa existente. La huella tampoco fija identidad completa: cambios de propietario, por ejemplo, no alteran el hash calculado.

- **e. Fases siguientes.** No identifico una columna imprescindible ausente. El estado conserva última marca humana y último cambio; el historial admite caducidad con autor nulo. El índice `(nivel, lead_id)` sirve para filtros; un índice temporal para caducidad debe decidirse con su consulta y volumen. La tarea necesitará una vía privilegiada propia, puesto que `service_role` está excluido. Además, conviene resolver una ambigüedad: negocio dice «sin gestión», mientras los comentarios permiten reiniciar el plazo mediante otra marca. La fase 1 todavía no ejecuta esa caducidad.

- **f. 55000 después de autorizar.** Es aceptable en el flujo nominal: solo revela la bandera respecto de un lead que el actor ya puede consultar. Ajeno, inexistente e inactivo conservan el mismo rechazo. No encuentro una filtración adicional por ese orden.

**Riesgos y test gaps**

- Faltan pruebas con dos sesiones para marcas simultáneas, reasignación/cierre concurrente y reversa frente a escrituras pendientes.
- `marcado_en >= v_marcado_en` pasa incluso si se elimina la actualización de `marcado_en`. Sembrar una fecha anterior permitiría verificar el reinicio. Conviene sembrar también `leads.actualizado_en` con una fecha distinta de `now()` para detectar cualquier actualización indebida.
- La comprobación de auditoría cuenta disparadores; no verifica filas de `audit_log`, actor ni valores registrados.
- La inmutabilidad se garantiza con disparadores habilitados en sesiones normales. No protege contra un administrador que deshabilite los disparadores.
- Migración, sintética y `check:scripts`: **PASS reportado**. `test:rls:preflight`: **NOT RUN reportado**. Ejecución independiente por este revisor: **NOT RUN**.

**NEXT ACTIONS**

Corregir F1–F4, reforzar el postflight según F5 y añadir pruebas concurrentes que reproduzcan las dos carreras. Después, ejecutar el bloque API corregido en un entorno que controle las escrituras y resolver los invariantes pendientes de parqueo y etapa.

**CONFIDENCE**

Alta en los defectos identificados por los fragmentos; limitada respecto de membresías heredadas, restricciones no transcritas y colisiones con candados existentes.
