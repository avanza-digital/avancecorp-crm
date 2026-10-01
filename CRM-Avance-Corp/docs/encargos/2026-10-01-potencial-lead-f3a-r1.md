ROLE: SECONDARY_REVIEWER.
Do not modify files. Do not implement the task. Do not invoke Claude. Do not delegate to another coding agent. Do not create another review chain.

# Encargo de revisión — RONDA 1 (LEVEL 3: puerta DEFINER de lectura que copia una policy) · Potencial del lead, FASE 3 entrega A (servidor)

Eres el revisor secundario. Sin base de datos ni red: todo está transcrito abajo. Responde con VERDICT (APPROVE / CHANGES_REQUESTED), SUMMARY, FINDINGS P0–P3 con evidencia (archivo/línea/fragmento), riesgos y test gaps, NEXT ACTIONS y CONFIDENCE. Sin hallazgo sin evidencia; separa hechos de hipótesis. Te pido REFUTAR, no confirmar.

## Negocio (decisiones de Miguel, 30/09 y 01/10)
Los analistas marcan cada lead como Frío, Tibio o Estrella («potencial del lead»). Marcan el analista dueño y su supervisor; gerencia y directorio solo ven. La marca baja sola: Estrella → Tibio con 5 días sin gestión, Tibio → Frío con 10 (lunes a sábado; cada contacto o volver a marcar reinicia). Confirmado el 01/10: una Estrella llega a Frío a los 10 días en total; el tiempo con el lead cerrado cuenta; solo el contacto real reinicia; al reasignar, la marca viaja con el lead. La fase 1 (tablas y puerta de marcar) está EN PRODUCCIÓN con la bandera `potencial_lead` APAGADA. La fase 2 (caducidad diaria) está revisada y fusionada, pendiente de aplicar. Esta entrega añade la PUERTA DE LECTURA para la pantalla (chip en listas, sección en la ficha con «baja a Tibio el …»).

## Decisiones a refutar
1. Lectura APARTE por lote (`crm.potencial_leads_fn(uuid[])`, molde `crm.cierres_estado_fn`, transcrito abajo) en vez de añadir una clave a las puertas existentes: la tabla de Leads y el Pipeline leen de `crm.cartera_filtrada_fn` (INVOKER, contrato con eco), la ficha lee `crm.leads` directo y la cola de hoy sale de puertas selladas por md5 (`private.assert_cola_v3`, `assert_gestion_diaria_analista`). La pantalla une por `lead_id`.
2. `SECURITY DEFINER` (las tablas de la marca no tienen grants para la API; el reloj y la regla de la fase 2 no tienen EXECUTE para la API) con el ESPEJO de la policy `leads_select` copiado en el núcleo, y el gate restrictivo `private.puede_acceder_crm()` INVOCADO en la puerta. El preflight fija por md5 las dos policies de lectura de `crm.leads` y seis ayudantes.
3. Un ítem por CADA lead pedido que el actor puede ver, también sin marca (`nivel: null`), para llevar `puede_marcar` a la ficha.
4. `puede_marcar` = `private.potencial_rechazo(actor, lead) = 'ok'`: la misma función que decide en la puerta de marcar, pero aquí SIN candado (es informativo; la puerta de marcar vuelve a decidir bajo candado).
5. `baja_el` = la primera fecha, de hoy en adelante, en que la regla de la fase 2 da un nivel menor (hoy mismo si la bajada está pendiente); `baja_a` = ese nivel. Null para leads cerrados, frío y sin marca.
6. `dias_sin_gestion` y `baja_el` se calculan con hoy = fecha de Lima de `now()` y corte = `now()`.
7. Con la bandera apagada: `{version:1, habilitada:false, items:[]}` sin leer nada; la admisión (sesión + gate) va ANTES de la bandera.
8. Las dos funciones son STABLE y no usan agregados de conteo (hay un censo diario, `private.contadores_crudos_leads_citas`, que marca toda función que nombre `crm.leads` y cuente).
9. `nivel_marcado` = `nivel_nuevo` del último evento con `motivo = 'manual'`.

## Preguntas
a. ¿Algún actor obtiene un ítem (o un dato por canal lateral: `puede_marcar`, errores, orden) de un lead que su RLS no le deja ver? Mira los NULL del espejo (`v_lector` null, `v_rol` null, `vendedor_id` null) y el caso de `p_actor` distinto de la sesión.
b. ¿El preflight puede dar falso rojo en producción (md5 de `pg_get_expr` con `search_path` vacío; `polroles::regrole[]::text`) o falso verde (una policy de lectura que no cace)?
c. ¿`baja_el` y `baja_a` coinciden SIEMPRE con lo que hará `private.potencial_caducar` (transcrita abajo)? Casos: domingo, bajada pendiente, límite del lote, lead bloqueado, contacto entre la lectura y la corrida, cambio de día entre `now()` de la lectura y las 05:10.
d. ¿Costo: `private.potencial_rechazo` por fila (hasta 200) — medido 33 ms con 200 ids — tiene algún caso patológico (supervisor con subárbol grande)?
e. ¿Zona horaria: `marcado_en` viaja como timestamptz en el JSON y `baja_el` como fecha de Lima; algo que la pantalla pueda malinterpretar?
f. ¿El postflight tiene falsos verdes (p. ej. ACL, `proconfig`)? ¿La reversa deja algo?
g. ¿Falta algún caso en la prueba sintética o en el bloque del gate?

## Evidencia (banco Docker propio: esquema de producción del 30/09 + las migraciones posteriores del repo)
- Ciclo: migración PASS → repetida se niega (PREFLIGHT ya aplicada) → reversa PASS → reversa repetida se niega → migración PASS. Registrar ×2 idempotente; verificar: EXECUTE puerta [authenticated,postgres], EXECUTE ajeno en el núcleo 0, forma DEFINER/s/search_path="".
- Trinquetes: los 36 `private.assert_*()` sin argumentos y el censo de contadores dan EXACTAMENTE lo mismo sin y con la migración (26 pasan, 10 caen igual por falta de datos en el banco).
- prueba-lectura.sql (abajo): 72 de 72. Fase 1 sintética 75/75 y fase 2 51/51 sin regresión.
- Mutantes de lógica (22): cazados ve-inactivos (13 fallas), sin-ambito (17), sin-propios (28), sin-parqueo (8), sin-gerencia (3), sin-lector (3), puede-siempre (12), puede-nunca (19), marcado-cualquier-evento (1), marcado-el-primero (5), sin-zona-lima (1), reloj-sin-contactos (1), corte-infinito (1), dias-hasta-manana (12), baja-desde-manana (3), cerrados-bajan (2), baja-nivel-fijo (3), sin-gate (2), sin-bandera (2), sin-tope (1), sin-sesion-ni-gate (4). Sobrevive A PROPÓSITO sin-sesion (sin sesión el gate ya rechaza con el mismo 42501).
- Mutantes de la migración y del preflight (12), todos rechazados: puerta INVOKER, VOLATILE, sin search_path, con EXECUTE para anon, sin grant; núcleo abierto, núcleo DEFINER, con conteo; un ayudante cambiado, una policy restrictiva nueva en crm.leads, leads_select cambiada, sin la fase 2.
- Medición: analista 50 ids = 9,7 ms y 200 ids = 34,2 ms; supervisor 50 ids = 9,0 ms y 200 ids = 33,5 ms (200 ítems, todos con marca y la mitad con contacto).
- `test:rls:preflight` (el gate con sesiones reales): NOT RUN en local (exige el gestor de credenciales); `node --check` del archivo: PASS.

## Archivos

### supabase/migrations/20261001151704_crm_potencial_lead_lectura.sql (NUEVA)
```sql
-- 20261001151704_crm_potencial_lead_lectura.sql
--
-- Potencial del lead · FASE 3, entrega A (servidor): la puerta de LECTURA. Plan aprobado por
-- Miguel el 01/10/2026 («vamos dale» al plan en dos entregas: A marcar y ver, B filtrar). Nota
-- del vault: «Potencial del lead - Frio Tibio Estrella (2026-09-30)», «Fase 3 · mapa y plan».
--
-- QUÉ HACE
--   · private.potencial_lectura(actor, lead_ids, hoy, corte): por cada lead pedido que el actor
--     PUEDE VER (espejo de la policy leads_select), la marca vigente y lo que la pantalla tiene
--     que decir: nivel, origen (manual | caducidad), el último nivel que puso una PERSONA,
--     cuándo se marcó, los días completos sin gestión (lunes a sábado), a qué nivel bajará y en
--     qué madrugada si nadie gestiona, y si el actor puede marcarlo. Un lead visible sin marca
--     viaja con nivel null. UNA sola regla: los días salen de private.potencial_reloj y
--     private.dias_lunes_a_sabado, el nivel siguiente de private.potencial_nivel_tras (fase 2), y
--     el permiso de private.potencial_rechazo (la misma función que decide en la puerta de
--     marcar, fase 1). Recibe hoy y el instante de corte para poder ensayarse con calendario.
--   · crm.potencial_leads_fn(uuid[]): la puerta. Sesión, el gate restrictivo del CRM
--     (private.puede_acceder_crm, invocado y no copiado), tope de 200 ids y la bandera
--     'potencial_lead': apagada devuelve {version:1, habilitada:false, items:[]} SIN leer nada;
--     encendida, {version:1, habilitada:true, items:[…]}.
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
  -- Texto de catálogo independiente de la sesión: todo calificado.
  perform pg_catalog.set_config('search_path', '', true);

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
         or (n.nspname = 'private' and p.proname = 'potencial_lectura'))
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

-- ── 1 · Núcleo de la lectura ──────────────────────────────────────────────────
create function private.potencial_lectura(p_actor uuid, p_lead_ids uuid[], p_hoy date, p_corte timestamptz)
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
  if p_actor is null or p_hoy is null or p_corte is null then
    raise exception 'Actor, fecha e instante de corte requeridos' using errcode = '22023';
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
    -- La primera madrugada (de hoy en adelante) en que la tarea la bajaría si nadie gestiona, y a
    -- qué nivel. Solo leads abiertos: la tarea no toca los cerrados. Qué niveles bajan lo dice la
    -- regla (frío nunca da un nivel menor; sin marca no hay nivel). 21 días cubren de sobra los 10
    -- días hábiles más sus domingos.
    left join lateral (
      select private.potencial_nivel_tras(p.nivel, private.dias_lunes_a_sabado(r.reloj_dia, g.dia::date)) as baja_a,
             g.dia::date as baja_el
      from pg_catalog.generate_series(p_hoy::timestamp, (p_hoy + 21)::timestamp, interval '1 day') g(dia)
      where l.etapa is not null and l.etapa not in ('convertido', 'descartado')
        and private.potencial_nivel_tras(p.nivel, private.dias_lunes_a_sabado(r.reloj_dia, g.dia::date)) < p.nivel
      order by g.dia
      limit 1
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
comment on function private.potencial_lectura(uuid, uuid[], date, timestamptz) is
'Lectura de la marca de potencial: un ítem por cada lead pedido que el actor puede ver (espejo de la policy leads_select; el actor debe ser el de la sesión). Por lead: nivel vigente (null sin marca), origen, último nivel puesto por una persona, cuándo, días completos sin gestión (lunes a sábado), a qué nivel bajará y en qué madrugada, y si el actor puede marcarlo (private.potencial_rechazo). No mira la bandera ni admite al actor: eso lo hace la puerta. Sin EXECUTE para la API.';

-- ── 2 · Puerta ─────────────────────────────────────────────────────────────────
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
      v_actor, p_lead_ids, (pg_catalog.now() at time zone 'America/Lima')::date, pg_catalog.now())
  );
end;
$function$;
comment on function crm.potencial_leads_fn(uuid[]) is
'Puerta de lectura del potencial del lead. Devuelve {version, habilitada, items}: con la bandera potencial_lead apagada, habilitada=false e items vacío; encendida, un ítem por cada lead pedido que el actor puede ver: {lead_id, nivel, origen, nivel_marcado, marcado_en, dias_sin_gestion, baja_a, baja_el, puede_marcar}. Máximo 200 ids (22023). Sin sesión o fuera del CRM: 42501. Solo lectura.';

-- ── 3 · Dueños y permisos ──────────────────────────────────────────────────────
alter function private.potencial_lectura(uuid, uuid[], date, timestamptz) owner to postgres;
alter function crm.potencial_leads_fn(uuid[]) owner to postgres;
revoke all on function private.potencial_lectura(uuid, uuid[], date, timestamptz) from public, anon, authenticated, service_role;
revoke all on function crm.potencial_leads_fn(uuid[]) from public, anon, authenticated, service_role;
grant execute on function crm.potencial_leads_fn(uuid[]) to authenticated;

-- ── 4 · Postflight ─────────────────────────────────────────────────────────────
do $postflight$
declare
  v_puerta pg_catalog.regprocedure := 'crm.potencial_leads_fn(uuid[])'::pg_catalog.regprocedure;
  v_nucleo pg_catalog.regprocedure := 'private.potencial_lectura(uuid,uuid[],date,timestamp with time zone)'::pg_catalog.regprocedure;
begin
  perform pg_catalog.set_config('search_path', '', true);

  -- Puerta: DEFINER, STABLE, dueño postgres, search_path vacío, EXECUTE solo authenticated.
  if (
    exists (
      select 1 from pg_catalog.pg_proc p
      where p.oid = v_puerta and p.prosecdef and p.proowner = 'postgres'::pg_catalog.regrole
        and p.provolatile = 's'
        and p.proconfig is not null and p.proconfig @> array['search_path=""']::text[]
        and p.proacl is not null
    )
    and not exists (select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
                    where p.oid = v_puerta
                      and a.grantee not in ('postgres'::pg_catalog.regrole, 'authenticated'::pg_catalog.regrole))
    and exists (select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
                where p.oid = v_puerta and a.privilege_type = 'EXECUTE' and a.grantee = 'authenticated'::pg_catalog.regrole)
  ) is not true then
    raise exception 'POSTFLIGHT potencial_lectura: la puerta no quedó DEFINER/STABLE/postgres/search_path vacío/EXECUTE solo authenticated';
  end if;

  -- Núcleo: INVOKER, STABLE, dueño postgres, search_path vacío y ACL explícita solo de postgres.
  if (
    exists (
      select 1 from pg_catalog.pg_proc p
      where p.oid = v_nucleo and not p.prosecdef and p.proowner = 'postgres'::pg_catalog.regrole
        and p.provolatile = 's'
        and p.proconfig is not null and p.proconfig @> array['search_path=""']::text[]
        and p.proacl is not null
    )
    and not exists (select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
                    where p.oid = v_nucleo and a.grantee <> 'postgres'::pg_catalog.regrole)
  ) is not true then
    raise exception 'POSTFLIGHT potencial_lectura: el núcleo no quedó INVOKER/STABLE/search_path vacío/sin EXECUTE para la API';
  end if;

  -- Ninguna de las dos cuenta filas (censo de contadores crudos de leads y citas).
  if exists (select 1 from pg_catalog.pg_proc p
             where p.oid in (v_puerta, v_nucleo) and p.prosrc ~* '(count|sum)\s*\(') then
    raise exception 'POSTFLIGHT potencial_lectura: una de las funciones usa un agregado de conteo';
  end if;

  -- Contrato mínimo que no depende de datos ni de la sesión: sin ids, lista vacía.
  if (
    private.potencial_lectura('00000000-0000-0000-0000-000000000000'::uuid, null,
                              (pg_catalog.now() at time zone 'America/Lima')::date, pg_catalog.now()) = '[]'::jsonb
    and private.potencial_lectura('00000000-0000-0000-0000-000000000000'::uuid, array[]::uuid[],
                                  (pg_catalog.now() at time zone 'America/Lima')::date, pg_catalog.now()) = '[]'::jsonb
  ) is not true then
    raise exception 'POSTFLIGHT potencial_lectura: sin ids el núcleo no devuelve una lista vacía';
  end if;

  raise notice 'potencial_lectura OK: núcleo INVOKER sin EXECUTE de la API, puerta DEFINER STABLE solo authenticated, sin conteos.';
end;
$postflight$;

commit;
```

### supabase/scripts/potencial-lead/reversa-lectura.sql
```sql
-- REVERSA de 20261001151704_crm_potencial_lead_lectura (fase 3, entrega A).
-- Quita la puerta de lectura y su núcleo. No hay datos que perder: las marcas y su historial son de
-- las fases 1 y 2 y se quedan. Con la puerta quitada, la pantalla recibe «función inexistente» y lo
-- trata como potencial apagado (no pinta nada). Conserva la fila de schema_migrations: anotarlo en
-- MIGRACIONES.md. Debe correr ANTES que las reversas de las fases 2 y 1.
begin;
set local lock_timeout = '5s';
do $chk$
begin
  if (
    pg_catalog.to_regprocedure('crm.potencial_leads_fn(uuid[])') is not null
    and pg_catalog.to_regprocedure('private.potencial_lectura(uuid,uuid[],date,timestamp with time zone)') is not null
  ) is not true then
    raise exception 'REVERSA potencial_lectura: la puerta de lectura no está aplicada';
  end if;
end;
$chk$;

drop function crm.potencial_leads_fn(uuid[]);
drop function private.potencial_lectura(uuid, uuid[], date, timestamptz);

do $post$
begin
  if exists (
    select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where (n.nspname = 'crm' and p.proname = 'potencial_leads_fn')
       or (n.nspname = 'private' and p.proname = 'potencial_lectura')
  ) then
    raise exception 'REVERSA potencial_lectura: quedaron funciones';
  end if;
  raise notice 'REVERSA potencial_lectura OK: sin puerta ni núcleo de lectura (las marcas se conservan).';
end;
$post$;
commit;
```

### supabase/scripts/potencial-lead/verificar-lectura.sql
```sql
-- VERIFICACIÓN (solo lectura, termina SIEMPRE en raise) de 20261001151704_crm_potencial_lead_lectura.
-- Se corre en producción después de aplicar y registrar. No escribe nada.
do $v$
declare
  v_puerta text; v_nucleo int; v_forma text; v_bandera boolean; v_marcas int; v_registro text;
begin
  select string_agg(x.grantee::regrole::text, ',' order by x.grantee::regrole::text) into v_puerta
    from pg_proc p, aclexplode(p.proacl) x
   where p.oid = 'crm.potencial_leads_fn(uuid[])'::regprocedure and x.privilege_type = 'EXECUTE';
  select count(*) into v_nucleo from pg_proc p, aclexplode(p.proacl) x
   where p.oid = 'private.potencial_lectura(uuid,uuid[],date,timestamp with time zone)'::regprocedure
     and x.grantee <> 'postgres'::regrole;
  select (case when p.prosecdef then 'DEFINER' else 'INVOKER' end) || '/' || p.provolatile::text || '/' || coalesce(array_to_string(p.proconfig, ','), '')
    into v_forma from pg_proc p where p.oid = 'crm.potencial_leads_fn(uuid[])'::regprocedure;
  select f.activo into v_bandera from crm.multiempresa_flags f where f.nombre = 'potencial_lead';
  select count(*) into v_marcas from crm.lead_potencial;
  select coalesce(max(name), '(sin registrar)') into v_registro
    from supabase_migrations.schema_migrations where version = '20261001151704';
  raise exception 'VERIFICAR potencial_lectura: EXECUTE puerta [%] (debe ser authenticated,postgres), EXECUTE ajeno en el núcleo % (debe ser 0), forma [%] (debe ser DEFINER/s/search_path=""), bandera %, marcas %, registro %',
    coalesce(v_puerta, '(ninguno)'), v_nucleo, coalesce(v_forma, '(no existe)'), coalesce(v_bandera::text, '(no existe)'), v_marcas, v_registro;
end $v$;
```

### supabase/scripts/potencial-lead/prueba-lectura.sql
```sql
-- Prueba sintética de 20261001151704_crm_potencial_lead_lectura (fase 3, entrega A).
-- SOLO en un banco, como supabase_admin, en UNA transacción que termina en raise (no deja nada).
-- ⚠️ Nunca se llama a una función sin EXECUTE bajo `set role` (tumba Postgres 17.6 con plan_filter):
-- el núcleo se llama como supabase_admin con la sesión del actor fijada; la puerta, como authenticated.
--
-- Mundo: gerencia G · supervisor S1 con sub-supervisor S1n · analista V1 (de S1) y V1n (de S1n) ·
-- supervisor S2 con analista V2 · coordinador C · directorio D · X con equipo inactivo.
-- Calendario simulado (hora de Lima): las marcas se ponen el lunes 2026-10-05 10:00.
--   L1  V1  contactado  estrella (antes tibio)      L1n V1n nuevo       tibio
--   L2  V2  contactado  estrella + contacto jue 08  LP  parqueado en S1 frío
--   LC  V1  convertido  estrella (congelada)        LD  V1  descartado  tibio (congelada)
--   LI  V1  INACTIVO    estrella (nadie lo ve)      L3  V1  contactado  sin marca
--   LPV parqueado con «supervisor» V1, sin marca    LK  V1  contactado  tibio que BAJÓ SOLA de estrella
--   LZ  V1  contactado  estrella marcada vie 09 21:00 Lima (en UTC ya es sábado)
--   LS  SIN ASIGNAR (sin analista ni supervisor), sin marca: solo lo ven gerencia y directorio, y
--       es el único lead que depende de la rama «rol = gerencia» de la policy.
--   NADA: un id que no existe.
begin;
set local lock_timeout = '5s';

create temp table act (k text primary key, id uuid not null default gen_random_uuid()) on commit drop;
insert into act (k) values ('G'), ('S1'), ('S1n'), ('V1'), ('V1n'), ('S2'), ('V2'), ('C'), ('D'), ('X');
create temp table lds (k text primary key, id uuid not null default gen_random_uuid()) on commit drop;
insert into lds (k) values ('L1'), ('L1n'), ('L2'), ('LP'), ('LC'), ('LD'), ('LI'), ('L3'), ('LPV'), ('LK'), ('LZ'), ('LS'), ('NADA');
create temp table res (n serial, caso text, esperado text, obtenido text) on commit drop;

create function pg_temp.a(p_k text) returns uuid language sql as $$ select id from act where k = p_k $$;
create function pg_temp.l(p_k text) returns uuid language sql as $$ select id from lds where k = p_k $$;
create function pg_temp.todos() returns uuid[] language sql as $$ select array_agg(id) from lds $$;
create function pg_temp.esperar(p_caso text, p_esperado text, p_obtenido text) returns void language sql as $$
  insert into res (caso, esperado, obtenido) values (p_caso, p_esperado, coalesce(p_obtenido, '(null)'))
$$;
create function pg_temp.lima(p_texto text) returns timestamptz language sql as $$
  select (p_texto::timestamp at time zone 'America/Lima')
$$;

-- Fixtures sin disparadores (solo filas que cumplen los CHECK).
set local session_replication_role = replica;
insert into auth.users (id, email) select id, lower(k) || '@lectura.banco' from act;
insert into public.perfiles (id, nombre_completo, rol, activo)
  select id, 'LECTURA ' || k, case k when 'D' then 'directorio' when 'G' then 'admin' else 'analista' end, true from act;
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
  (pg_temp.l('L1'),  'LECTURA L1',  '+51987640001', 'landing', 50000, 'PEN', 'contactado', pg_temp.a('V1'),  null, true, null),
  (pg_temp.l('L1n'), 'LECTURA L1N', '+51987640002', 'landing', 15000, 'PEN', 'nuevo',      pg_temp.a('V1n'), null, true, null),
  (pg_temp.l('L2'),  'LECTURA L2',  '+51987640003', 'landing', 30000, 'PEN', 'contactado', pg_temp.a('V2'),  null, true, null),
  (pg_temp.l('LP'),  'LECTURA LP',  '+51987640004', 'landing', 12000, 'PEN', 'nuevo',      null, pg_temp.a('S1'), true, null),
  (pg_temp.l('LC'),  'LECTURA LC',  '+51987640005', 'landing', 20000, 'PEN', 'convertido', pg_temp.a('V1'),  null, true, null),
  (pg_temp.l('LD'),  'LECTURA LD',  '+51987640006', 'landing', 20000, 'PEN', 'descartado', pg_temp.a('V1'),  null, true, 'sin_interes'),
  (pg_temp.l('LI'),  'LECTURA LI',  '+51987640007', 'landing', 20000, 'PEN', 'contactado', pg_temp.a('V1'),  null, false, null),
  (pg_temp.l('L3'),  'LECTURA L3',  '+51987640008', 'landing', 20000, 'PEN', 'contactado', pg_temp.a('V1'),  null, true, null),
  (pg_temp.l('LPV'), 'LECTURA LPV', '+51987640009', 'landing', 20000, 'PEN', 'nuevo',      null, pg_temp.a('V1'), true, null),
  (pg_temp.l('LK'),  'LECTURA LK',  '+51987640010', 'landing', 20000, 'PEN', 'contactado', pg_temp.a('V1'),  null, true, null),
  (pg_temp.l('LZ'),  'LECTURA LZ',  '+51987640011', 'landing', 20000, 'PEN', 'contactado', pg_temp.a('V1'),  null, true, null),
  (pg_temp.l('LS'),  'LECTURA LS',  '+51987640012', 'landing', 20000, 'PEN', 'nuevo',      null, null, true, null);
insert into crm.lead_potencial (lead_id, nivel, origen, marcado_por, marcado_en) values
  (pg_temp.l('L1'),  'estrella', 'manual',    pg_temp.a('V1'),  pg_temp.lima('2026-10-05 10:00')),
  (pg_temp.l('L1n'), 'tibio',    'manual',    pg_temp.a('S1n'), pg_temp.lima('2026-10-05 10:00')),
  (pg_temp.l('L2'),  'estrella', 'manual',    pg_temp.a('V2'),  pg_temp.lima('2026-10-05 10:00')),
  (pg_temp.l('LP'),  'frio',     'manual',    pg_temp.a('S1'),  pg_temp.lima('2026-10-05 10:00')),
  (pg_temp.l('LC'),  'estrella', 'manual',    pg_temp.a('V1'),  pg_temp.lima('2026-10-05 10:00')),
  (pg_temp.l('LD'),  'tibio',    'manual',    pg_temp.a('V1'),  pg_temp.lima('2026-10-05 10:00')),
  (pg_temp.l('LI'),  'estrella', 'manual',    pg_temp.a('V1'),  pg_temp.lima('2026-10-05 10:00')),
  (pg_temp.l('LK'),  'tibio',    'caducidad', pg_temp.a('V1'),  pg_temp.lima('2026-10-05 10:00')),
  (pg_temp.l('LZ'),  'estrella', 'manual',    pg_temp.a('V1'),  pg_temp.lima('2026-10-09 21:00'));
insert into crm.lead_potencial_eventos (lead_id, nivel_anterior, nivel_nuevo, motivo, por, creado_en) values
  (pg_temp.l('L1'),  null,       'tibio',    'manual',    pg_temp.a('V1'),  pg_temp.lima('2026-10-02 09:00')),
  (pg_temp.l('L1'),  'tibio',    'estrella', 'manual',    pg_temp.a('V1'),  pg_temp.lima('2026-10-05 10:00')),
  (pg_temp.l('L1n'), null,       'tibio',    'manual',    pg_temp.a('S1n'), pg_temp.lima('2026-10-05 10:00')),
  (pg_temp.l('L2'),  null,       'estrella', 'manual',    pg_temp.a('V2'),  pg_temp.lima('2026-10-05 10:00')),
  (pg_temp.l('LP'),  null,       'frio',     'manual',    pg_temp.a('S1'),  pg_temp.lima('2026-10-05 10:00')),
  (pg_temp.l('LC'),  null,       'estrella', 'manual',    pg_temp.a('V1'),  pg_temp.lima('2026-10-05 10:00')),
  (pg_temp.l('LD'),  null,       'tibio',    'manual',    pg_temp.a('V1'),  pg_temp.lima('2026-10-05 10:00')),
  (pg_temp.l('LI'),  null,       'estrella', 'manual',    pg_temp.a('V1'),  pg_temp.lima('2026-10-05 10:00')),
  (pg_temp.l('LK'),  null,       'estrella', 'manual',    pg_temp.a('V1'),  pg_temp.lima('2026-10-05 10:00')),
  (pg_temp.l('LK'),  'estrella', 'tibio',    'caducidad', null,             pg_temp.lima('2026-10-11 05:10')),
  (pg_temp.l('LZ'),  null,       'estrella', 'manual',    pg_temp.a('V1'),  pg_temp.lima('2026-10-09 21:00'));
-- L2: un CONTACTO el jueves 10-08 15:00 reinicia su reloj.
insert into crm.actividades (lead_id, tipo, detalle, creado_por, creado_en) values
  (pg_temp.l('L2'), 'llamada_no_contestada', 'prueba de lectura', pg_temp.a('V2'), pg_temp.lima('2026-10-08 15:00'));
set local session_replication_role = origin;

-- Identidad de la sesión, en las DOS formas (producción lee request.jwt.claims; la imagen del banco
-- solo request.jwt.claim.sub).
create function pg_temp.sesion(p_actor uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', coalesce(p_actor::text, ''), true),
         set_config('request.jwt.claims',
           case when p_actor is null then '' else json_build_object('sub', p_actor, 'role', 'authenticated')::text end, true);
$$;

-- El núcleo con calendario simulado: la corrida de las 05:10 Lima de p_hoy (o el corte que se pida).
create function pg_temp.leer(p_actor uuid, p_ids uuid[], p_hoy date, p_corte timestamptz default null) returns jsonb language plpgsql as $f$
begin
  perform pg_temp.sesion(p_actor);
  return private.potencial_lectura(p_actor, p_ids, p_hoy, coalesce(p_corte, (p_hoy::timestamp + time '05:10') at time zone 'America/Lima'));
end $f$;

-- Un ítem resumido: nivel/origen/nivel_marcado · días · baja_a@baja_el · puede.
create function pg_temp.item(p_items jsonb, p_k text) returns text language sql as $$
  select coalesce((
    select coalesce(i ->> 'nivel', '-') || '/' || coalesce(i ->> 'origen', '-') || '/' || coalesce(i ->> 'nivel_marcado', '-')
           || ' d=' || coalesce(i ->> 'dias_sin_gestion', '-')
           || ' baja=' || coalesce(i ->> 'baja_a', '-') || '@' || coalesce(i ->> 'baja_el', '-')
           || ' puede=' || (i ->> 'puede_marcar')
    from jsonb_array_elements(p_items) i where (i ->> 'lead_id')::uuid = pg_temp.l(p_k)), '(no viaja)')
$$;
-- Las claves de los leads que trae una lista de ítems.
create function pg_temp.claves(p_items jsonb) returns text language sql as $$
  select coalesce(string_agg(d.k, ',' order by d.k), '(ninguno)')
  from jsonb_array_elements(p_items) i join lds d on d.id = (i ->> 'lead_id')::uuid
$$;

-- La puerta, como la llama la pantalla: authenticated. Devuelve el sobre o {"error": SQLSTATE}.
create function pg_temp.puerta(p_actor uuid, p_ids uuid[]) returns jsonb language plpgsql as $f$
declare v jsonb;
begin
  perform pg_temp.sesion(p_actor);
  set local role authenticated;
  begin
    v := crm.potencial_leads_fn(p_ids);
    reset role;
    return v;
  exception when others then
    reset role;
    return jsonb_build_object('error', sqlstate);
  end;
end $f$;

-- Lo que la RLS REAL de crm.leads deja ver a un actor (la vara con la que se mide el espejo).
create function pg_temp.ve_rls(p_actor uuid) returns text language plpgsql as $f$
declare v_ids uuid[] := pg_temp.todos(); v_vistos uuid[];
begin
  perform pg_temp.sesion(p_actor);
  set local role authenticated;
  begin
    select array_agg(l.id) into v_vistos from crm.leads l where l.id = any (v_ids);
  exception when others then
    reset role;
    return 'error ' || sqlstate;
  end;
  reset role;
  return coalesce((select string_agg(d.k, ',' order by d.k) from lds d where d.id = any (v_vistos)), '(ninguno)');
end $f$;

-- ¿Puede marcar DE VERDAD? Se intenta por la puerta de la fase 1 y se deshace (subtransacción).
create function pg_temp.puede_real(p_actor uuid, p_lead uuid) returns boolean language plpgsql as $f$
begin
  perform pg_temp.sesion(p_actor);
  set local role authenticated;
  begin
    perform crm.marcar_potencial_lead_fn(p_lead, 'tibio'::crm.nivel_potencial);
    raise exception 'deshacer' using errcode = 'P9999';
  exception
    when sqlstate 'P9999' then reset role; return true;
    when others then reset role; return false;
  end;
end $f$;
-- «clave:t/f» de lo que la puerta dice que el actor puede marcar, y de lo que puede de verdad.
create function pg_temp.puede_puerta(p_actor uuid) returns text language sql as $$
  select coalesce(string_agg(d.k || ':' || left(i ->> 'puede_marcar', 1), ',' order by d.k), '(ninguno)')
  from jsonb_array_elements(pg_temp.puerta(p_actor, pg_temp.todos()) -> 'items') i
  join lds d on d.id = (i ->> 'lead_id')::uuid
$$;
create function pg_temp.puede_verdad(p_actor uuid) returns text language plpgsql as $f$
declare v text; v_items jsonb := pg_temp.puerta(p_actor, pg_temp.todos()) -> 'items';
begin
  select coalesce(string_agg(d.k || ':' || left(pg_temp.puede_real(p_actor, d.id)::text, 1), ',' order by d.k), '(ninguno)') into v
  from jsonb_array_elements(v_items) i join lds d on d.id = (i ->> 'lead_id')::uuid;
  return v;
end $f$;

do $prueba$
declare
  v jsonb;
  v_n integer;
  r record;
  v_muchos uuid[];
begin
  -- ── Permisos (del catálogo: nunca se llama sin EXECUTE bajo set role) ──
  perform pg_temp.esperar('EXECUTE de la puerta: authenticated sí; anon y service_role no', 'true/false/false',
    has_function_privilege('authenticated', 'crm.potencial_leads_fn(uuid[])', 'EXECUTE')::text || '/' ||
    has_function_privilege('anon', 'crm.potencial_leads_fn(uuid[])', 'EXECUTE')::text || '/' ||
    has_function_privilege('service_role', 'crm.potencial_leads_fn(uuid[])', 'EXECUTE')::text);
  perform pg_temp.esperar('EXECUTE del núcleo: nadie de la API', 'false/false/false',
    has_function_privilege('authenticated', 'private.potencial_lectura(uuid,uuid[],date,timestamptz)', 'EXECUTE')::text || '/' ||
    has_function_privilege('anon', 'private.potencial_lectura(uuid,uuid[],date,timestamptz)', 'EXECUTE')::text || '/' ||
    has_function_privilege('service_role', 'private.potencial_lectura(uuid,uuid[],date,timestamptz)', 'EXECUTE')::text);

  -- ── Bandera APAGADA: la puerta admite, pero no entrega nada ──
  perform pg_temp.esperar('bandera apagada al empezar', 'false', (select activo::text from crm.multiempresa_flags where nombre = 'potencial_lead'));
  perform pg_temp.esperar('apagada: V1 recibe habilitada=false y sin ítems', '{"items": [], "version": 1, "habilitada": false}',
    pg_temp.puerta(pg_temp.a('V1'), pg_temp.todos())::text);
  perform pg_temp.esperar('apagada: gerencia igual', '{"items": [], "version": 1, "habilitada": false}',
    pg_temp.puerta(pg_temp.a('G'), pg_temp.todos())::text);
  perform pg_temp.esperar('apagada: sin sesión sigue siendo 42501', '{"error": "42501"}', pg_temp.puerta(null, pg_temp.todos())::text);
  perform pg_temp.esperar('apagada: X (equipo inactivo) sigue siendo 42501', '{"error": "42501"}', pg_temp.puerta(pg_temp.a('X'), pg_temp.todos())::text);

  -- ── Bandera ENCENDIDA ──
  update crm.multiempresa_flags set activo = true where nombre = 'potencial_lead';

  -- Admisión y validación de la puerta.
  perform pg_temp.esperar('sin sesión → 42501', '{"error": "42501"}', pg_temp.puerta(null, pg_temp.todos())::text);
  perform pg_temp.esperar('X (equipo inactivo) → 42501', '{"error": "42501"}', pg_temp.puerta(pg_temp.a('X'), pg_temp.todos())::text);
  perform pg_temp.esperar('sin ids (null) → encendida y vacía', '{"items": [], "version": 1, "habilitada": true}', pg_temp.puerta(pg_temp.a('V1'), null)::text);
  perform pg_temp.esperar('sin ids (vacío) → encendida y vacía', '{"items": [], "version": 1, "habilitada": true}', pg_temp.puerta(pg_temp.a('V1'), array[]::uuid[])::text);
  select array_agg(gen_random_uuid()) into v_muchos from generate_series(1, 200);
  perform pg_temp.esperar('200 ids → pasa', 'true', (pg_temp.puerta(pg_temp.a('V1'), v_muchos) ->> 'habilitada'));
  perform pg_temp.esperar('201 ids → 22023', '{"error": "22023"}', pg_temp.puerta(pg_temp.a('V1'), v_muchos || gen_random_uuid())::text);

  -- Forma del sobre y del ítem.
  v := pg_temp.puerta(pg_temp.a('V1'), pg_temp.todos());
  perform pg_temp.esperar('sobre: version, habilitada, items', 'habilitada,items,version', (select string_agg(k, ',' order by k) from jsonb_object_keys(v) k));
  perform pg_temp.esperar('ítem: las 9 claves del contrato', 'baja_a,baja_el,dias_sin_gestion,lead_id,marcado_en,nivel,nivel_marcado,origen,puede_marcar',
    (select string_agg(k, ',' order by k) from jsonb_object_keys(v -> 'items' -> 0) k));
  perform pg_temp.esperar('ítems ordenados por lead_id', 'true',
    ((select array_agg(i ->> 'lead_id') from jsonb_array_elements(v -> 'items') i)
     = (select array_agg(x order by x) from (select i ->> 'lead_id' as x from jsonb_array_elements(v -> 'items') i) s))::text);
  perform pg_temp.esperar('ids repetidos: un ítem por lead', '1',
    jsonb_array_length(pg_temp.puerta(pg_temp.a('V1'), array[pg_temp.l('L1'), pg_temp.l('L1'), pg_temp.l('L1')]) -> 'items')::text);

  -- ── Visibilidad: lo que entrega la puerta por actor (LI inactivo y NADA no viajan nunca) ──
  perform pg_temp.esperar('V1 ve lo suyo (y LPV, parqueado a su nombre)', 'L1,L3,LC,LD,LK,LPV,LZ', pg_temp.claves(pg_temp.puerta(pg_temp.a('V1'), pg_temp.todos()) -> 'items'));
  perform pg_temp.esperar('V1n ve solo L1n', 'L1n', pg_temp.claves(pg_temp.puerta(pg_temp.a('V1n'), pg_temp.todos()) -> 'items'));
  perform pg_temp.esperar('S1n ve su subárbol', 'L1n', pg_temp.claves(pg_temp.puerta(pg_temp.a('S1n'), pg_temp.todos()) -> 'items'));
  perform pg_temp.esperar('S1 ve su subárbol y su parqueo', 'L1,L1n,L3,LC,LD,LK,LP,LPV,LZ', pg_temp.claves(pg_temp.puerta(pg_temp.a('S1'), pg_temp.todos()) -> 'items'));
  perform pg_temp.esperar('V2 ve solo L2', 'L2', pg_temp.claves(pg_temp.puerta(pg_temp.a('V2'), pg_temp.todos()) -> 'items'));
  perform pg_temp.esperar('S2 ve solo L2', 'L2', pg_temp.claves(pg_temp.puerta(pg_temp.a('S2'), pg_temp.todos()) -> 'items'));
  perform pg_temp.esperar('gerencia ve todo lo vivo, también lo sin asignar', 'L1,L1n,L2,L3,LC,LD,LK,LP,LPV,LS,LZ', pg_temp.claves(pg_temp.puerta(pg_temp.a('G'), pg_temp.todos()) -> 'items'));
  perform pg_temp.esperar('directorio (lector global) ve todo lo vivo', 'L1,L1n,L2,L3,LC,LD,LK,LP,LPV,LS,LZ', pg_temp.claves(pg_temp.puerta(pg_temp.a('D'), pg_temp.todos()) -> 'items'));
  perform pg_temp.esperar('coordinación: admitida y sin leads', '(ninguno)', pg_temp.claves(pg_temp.puerta(pg_temp.a('C'), pg_temp.todos()) -> 'items'));
  perform pg_temp.esperar('S1 no ve el lead sin asignar', '(ninguno)', pg_temp.claves(pg_temp.puerta(pg_temp.a('S1'), array[pg_temp.l('LS')]) -> 'items'));
  perform pg_temp.esperar('V2 preguntando por un lead ajeno: no viaja', '(ninguno)', pg_temp.claves(pg_temp.puerta(pg_temp.a('V2'), array[pg_temp.l('L1')]) -> 'items'));

  -- ── EQUIVALENCIA con la RLS real de crm.leads, actor por actor ──
  for r in select k, id from act where k <> 'X' order by k loop
    perform pg_temp.esperar('espejo = RLS real para ' || r.k, pg_temp.ve_rls(r.id), pg_temp.claves(pg_temp.puerta(r.id, pg_temp.todos()) -> 'items'));
  end loop;
  perform pg_temp.esperar('X: la RLS real tampoco le deja ver nada', '(ninguno)', pg_temp.ve_rls(pg_temp.a('X')));

  -- ── puede_marcar: lo que dice la puerta = lo que la puerta de marcar permite de verdad ──
  perform pg_temp.esperar('V1 puede marcar lo abierto y suyo (no cerrados ni parqueo)', 'L1:t,L3:t,LC:f,LD:f,LK:t,LPV:f,LZ:t', pg_temp.puede_puerta(pg_temp.a('V1')));
  perform pg_temp.esperar('S1 puede marcar su subárbol abierto y su parqueo', 'L1:t,L1n:t,L3:t,LC:f,LD:f,LK:t,LP:t,LPV:t,LZ:t', pg_temp.puede_puerta(pg_temp.a('S1')));
  perform pg_temp.esperar('gerencia ve pero no marca', 'L1:f,L1n:f,L2:f,L3:f,LC:f,LD:f,LK:f,LP:f,LPV:f,LS:f,LZ:f', pg_temp.puede_puerta(pg_temp.a('G')));
  perform pg_temp.esperar('directorio ve pero no marca', 'L1:f,L1n:f,L2:f,L3:f,LC:f,LD:f,LK:f,LP:f,LPV:f,LS:f,LZ:f', pg_temp.puede_puerta(pg_temp.a('D')));
  for r in select k, id from act where k not in ('X', 'C') order by k loop
    perform pg_temp.esperar('puede_marcar = marcar de verdad para ' || r.k, pg_temp.puede_verdad(r.id), pg_temp.puede_puerta(r.id));
  end loop;
  perform pg_temp.esperar('probar «puede de verdad» no dejó marcas nuevas', '9/11',
    (select count(*)::text from crm.lead_potencial where lead_id in (select id from lds)) || '/' ||
    (select count(*)::text from crm.lead_potencial_eventos where lead_id in (select id from lds)));

  -- ── El calendario (núcleo con fecha simulada, como V1 salvo que se diga) ──
  v := pg_temp.leer(pg_temp.a('V1'), pg_temp.todos(), '2026-10-06');
  perform pg_temp.esperar('mar 10-06 · L1 estrella recién marcada: 0 días, baja a tibio el dom 10-11', 'estrella/manual/estrella d=0 baja=tibio@2026-10-11 puede=true', pg_temp.item(v, 'L1'));
  perform pg_temp.esperar('mar 10-06 · L3 sin marca: todo null y puede marcar', '-/-/- d=- baja=-@- puede=true', pg_temp.item(v, 'L3'));
  perform pg_temp.esperar('mar 10-06 · LPV parqueado sin marca: V1 lo ve pero no lo marca', '-/-/- d=- baja=-@- puede=false', pg_temp.item(v, 'LPV'));
  perform pg_temp.esperar('mar 10-06 · LI inactivo no viaja', '(no viaja)', pg_temp.item(v, 'LI'));
  perform pg_temp.esperar('mar 10-06 · un id que no existe no viaja', '(no viaja)', pg_temp.item(v, 'NADA'));
  perform pg_temp.esperar('mar 10-06 · marcado_en viaja', '2026-10-05 10:00', (
    select to_char((i ->> 'marcado_en')::timestamptz at time zone 'America/Lima', 'YYYY-MM-DD HH24:MI')
    from jsonb_array_elements(v) i where (i ->> 'lead_id')::uuid = pg_temp.l('L1')));

  v := pg_temp.leer(pg_temp.a('V1'), pg_temp.todos(), '2026-10-10');
  perform pg_temp.esperar('sáb 10-10 · L1: 4 días (mar-vie), sigue bajando el dom 10-11', 'estrella/manual/estrella d=4 baja=tibio@2026-10-11 puede=true', pg_temp.item(v, 'L1'));
  v := pg_temp.leer(pg_temp.a('V1'), pg_temp.todos(), '2026-10-11');
  perform pg_temp.esperar('dom 10-11 · L1: 5 días, baja HOY (pendiente de la corrida)', 'estrella/manual/estrella d=5 baja=tibio@2026-10-11 puede=true', pg_temp.item(v, 'L1'));

  v := pg_temp.leer(pg_temp.a('V1'), pg_temp.todos(), '2026-10-12');
  perform pg_temp.esperar('lun 10-12 · LC convertido: conserva la estrella, no baja ni se marca', 'estrella/manual/estrella d=5 baja=-@- puede=false', pg_temp.item(v, 'LC'));
  perform pg_temp.esperar('lun 10-12 · LD descartado: conserva el tibio, no baja ni se marca', 'tibio/manual/tibio d=5 baja=-@- puede=false', pg_temp.item(v, 'LD'));
  perform pg_temp.esperar('lun 10-12 · LK bajó sola: tibio por caducidad, la persona puso estrella, baja a frío el sáb 10-17', 'tibio/caducidad/estrella d=5 baja=frio@2026-10-17 puede=true', pg_temp.item(v, 'LK'));
  perform pg_temp.esperar('lun 10-12 · LZ marcada vie 21:00 Lima: 1 día (el sábado), no 0', 'estrella/manual/estrella d=1 baja=tibio@2026-10-16 puede=true', pg_temp.item(v, 'LZ'));

  v := pg_temp.leer(pg_temp.a('V1'), pg_temp.todos(), '2026-10-19');
  perform pg_temp.esperar('lun 10-19 · L1 con 11 días sin corrida: va directo a frío, hoy', 'estrella/manual/estrella d=11 baja=frio@2026-10-19 puede=true', pg_temp.item(v, 'L1'));

  v := pg_temp.leer(pg_temp.a('S1'), pg_temp.todos(), '2026-10-06');
  perform pg_temp.esperar('mar 10-06 · L1n tibio: baja a frío el sáb 10-17 (10 días)', 'tibio/manual/tibio d=0 baja=frio@2026-10-17 puede=true', pg_temp.item(v, 'L1n'));
  v := pg_temp.leer(pg_temp.a('S1'), pg_temp.todos(), '2026-10-12');
  perform pg_temp.esperar('lun 10-12 · LP frío: no baja más', 'frio/manual/frio d=5 baja=-@- puede=true', pg_temp.item(v, 'LP'));

  v := pg_temp.leer(pg_temp.a('V2'), pg_temp.todos(), '2026-10-12');
  perform pg_temp.esperar('lun 10-12 · L2 con contacto el jue 10-08: 2 días, baja el jue 10-15', 'estrella/manual/estrella d=2 baja=tibio@2026-10-15 puede=true', pg_temp.item(v, 'L2'));
  v := pg_temp.leer(pg_temp.a('V2'), pg_temp.todos(), '2026-10-07');
  perform pg_temp.esperar('mié 10-07 · L2 antes de su contacto: el contacto futuro aún no cuenta', 'estrella/manual/estrella d=1 baja=tibio@2026-10-11 puede=true', pg_temp.item(v, 'L2'));

  v := pg_temp.leer(pg_temp.a('G'), pg_temp.todos(), '2026-10-12');
  perform pg_temp.esperar('gerencia · L1: ve la marca y cuándo baja, no marca', 'estrella/manual/estrella d=5 baja=tibio@2026-10-12 puede=false', pg_temp.item(v, 'L1'));

  -- Núcleo: argumentos.
  perform pg_temp.esperar('núcleo sin ids → []', '[]', pg_temp.leer(pg_temp.a('V1'), null, '2026-10-06')::text);
  begin
    perform private.potencial_lectura(null, pg_temp.todos(), '2026-10-06', now());
    perform pg_temp.esperar('núcleo sin actor → 22023', '22023', 'sin error');
  exception when others then
    perform pg_temp.esperar('núcleo sin actor → 22023', '22023', sqlstate);
  end;

  -- ── Solo lectura: nada cambió en las tablas de la marca ──
  perform pg_temp.esperar('la lectura no escribió marcas ni eventos', '9/11',
    (select count(*)::text from crm.lead_potencial where lead_id in (select id from lds)) || '/' ||
    (select count(*)::text from crm.lead_potencial_eventos where lead_id in (select id from lds)));

  -- ── Veredicto (el raise deshace todo) ──
  select count(*) into v_n from res where esperado is distinct from obtenido;
  if v_n = 0 then
    raise exception 'LECTURA potencial_lead: % de % OK', (select count(*) from res), (select count(*) from res) using errcode = 'P0001';
  else
    raise exception 'LECTURA potencial_lead: % FALLAS de %: %', v_n, (select count(*) from res),
      (select string_agg(n || ' ' || caso || ' → esperado ' || esperado || ', obtenido ' || obtenido, ' | ' order by n)
       from res where esperado is distinct from obtenido) using errcode = 'P0001';
  end if;
end;
$prueba$;
rollback;
```

### supabase/scripts/potencial-lead/banco/medir-lectura.sql
```sql
-- Cuánto tarda la puerta de lectura con una página (50 ids) y con el tope (200 ids), como analista y
-- como supervisor (el caso caro: su subárbol se resuelve en cada «puede marcar»). SOLO en un banco,
-- como supabase_admin; todo se deshace.
begin;
create temp table m_act (k text primary key, id uuid not null default gen_random_uuid()) on commit drop;
insert into m_act (k) values ('S'), ('V');
create temp table m_lds (n int primary key, id uuid not null default gen_random_uuid()) on commit drop;
insert into m_lds (n) select g from generate_series(1, 200) g;
set local session_replication_role = replica;
insert into auth.users (id, email) select id, lower(k) || '@medir-lectura.banco' from m_act;
insert into public.perfiles (id, nombre_completo, rol, activo) select id, 'MEDIR ' || k, 'analista', true from m_act;
insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo) values
  ((select id from m_act where k = 'S'), 'supervisor', null, true),
  ((select id from m_act where k = 'V'), 'vendedor', (select id from m_act where k = 'S'), true);
insert into crm.leads (id, nombre_completo, telefono, origen, monto_estimado, moneda, etapa, vendedor_id, activo)
select id, 'MEDIR ' || n, '+5198763' || lpad(n::text, 4, '0'), 'landing', 10000, 'PEN', 'contactado', (select id from m_act where k = 'V'), true from m_lds;
insert into crm.lead_potencial (lead_id, nivel, origen, marcado_por, marcado_en)
select id, (array['estrella', 'tibio', 'frio'])[1 + n % 3]::crm.nivel_potencial, 'manual', (select id from m_act where k = 'V'), now() - interval '3 days' from m_lds;
insert into crm.lead_potencial_eventos (lead_id, nivel_anterior, nivel_nuevo, motivo, por, creado_en)
select id, null, (array['estrella', 'tibio', 'frio'])[1 + n % 3]::crm.nivel_potencial, 'manual', (select id from m_act where k = 'V'), now() - interval '3 days' from m_lds;
insert into crm.actividades (lead_id, tipo, detalle, creado_por, creado_en)
select id, 'llamada_realizada', 'medición', (select id from m_act where k = 'V'), now() - interval '2 days' from m_lds where n % 2 = 0;
set local session_replication_role = origin;
update crm.multiempresa_flags set activo = true where nombre = 'potencial_lead';
do $m$
declare
  v_ids uuid[]; v jsonb; t0 timestamptz; r record; v_txt text := '';
  ms50 numeric; ms200 numeric;
begin
  select array_agg(id order by n) into v_ids from m_lds;
  for r in select k, id from m_act order by k desc loop
    perform set_config('request.jwt.claim.sub', r.id::text, true),
            set_config('request.jwt.claims', json_build_object('sub', r.id, 'role', 'authenticated')::text, true);
    set local role authenticated;
    v := crm.potencial_leads_fn(v_ids[1:5]);  -- calentamiento
    t0 := clock_timestamp(); v := crm.potencial_leads_fn(v_ids[1:50]);
    ms50 := extract(epoch from clock_timestamp() - t0) * 1000;
    t0 := clock_timestamp(); v := crm.potencial_leads_fn(v_ids);
    ms200 := extract(epoch from clock_timestamp() - t0) * 1000;
    reset role;
    v_txt := v_txt || format(' · %s: 50 ids = %s ms, 200 ids = %s ms (%s ítems)',
      case r.k when 'V' then 'analista' else 'supervisor' end, round(ms50, 1), round(ms200, 1), jsonb_array_length(v -> 'items'));
  end loop;
  raise exception 'MEDIR lectura%', v_txt using errcode = 'P0001';
end $m$;
rollback;
```

### supabase/scripts/test-rls.mjs (bloque NUEVO; `check`, `fail`, `expectExpectedFailure` y `contarFueraDeBanda` ya existen)
```js
// ── Potencial del lead (20261001151704): puerta de LECTURA crm.potencial_leads_fn ─────────────
// Solo lectura. Con la bandera 'potencial_lead' APAGADA (así nace) la puerta admite y devuelve
// habilitada=false sin ítems. Con la bandera ENCENDIDA, lo que entrega debe ser EXACTAMENTE lo que la
// RLS de crm.leads deja ver a ese actor (la puerta es DEFINER y copia la policy leads_select: esta
// comparación es la que caza un espejo desincronizado). El calendario («baja el…»), el «puede marcar»
// contra la puerta de marcar y los mutantes viven en supabase/scripts/potencial-lead/
// prueba-lectura.sql (72 casos, deshecha) y banco/ciclo-fase3a.sh. Salto RUIDOSO si la puerta no está
// en esta base o falta la vía fuera de banda; con CRM_RLS_EXIGE_POTENCIAL=1 es un FALLO.
async function testPotencialLectura(sessions, seed) {
  console.log('\n— Potencial del lead: puerta de lectura (sin escribir) —');
  const saltar = (msg) => {
    if (process.env.CRM_RLS_EXIGE_POTENCIAL === '1') fail(msg);
    else console.log(`  ${msg}`);
  };
  let aplicada;
  let encendida;
  try {
    aplicada = contarFueraDeBanda('potencial lectura: puerta aplicada',
      `select (to_regprocedure('crm.potencial_leads_fn(uuid[])') is not null)::int`);
    encendida = aplicada === 1 ? contarFueraDeBanda('potencial lectura: bandera',
      `select coalesce((select activo::int from crm.multiempresa_flags where nombre = 'potencial_lead'), 0)`) : 0;
  } catch (error) {
    saltar(`⚠ Lectura del potencial SALTADA: sin vía fuera de banda para leer la bandera (${error?.message ?? String(error)})`);
    return;
  }
  if (aplicada !== 1) {
    saltar('⚠ crm.potencial_leads_fn NO desplegada en esta base: bloque de lectura del potencial SALTADO (no probado)');
    return;
  }

  const FN = 'potencial_leads_fn';
  const ids = [...seed.leadByName.values()].map((lead) => lead.id).slice(0, 200);
  const leer = (cliente, lista = ids) => cliente.schema('crm').rpc(FN, { p_lead_ids: lista });
  const DENEGADO = /permission denied|denegado/i;

  for (const clave of ['vend1', 'vend3', 'sup1', 'sup1Nested', 'sup2', 'gerencia', 'coordinador', 'directorio']) {
    const { data, error } = await leer(sessions[clave].client);
    if (error) {
      fail(`potencial lectura ${clave}: error inesperado ${error.code ?? ''} ${error.message}`);
      continue;
    }
    check(data?.version === 1 && Array.isArray(data?.items) && data?.habilitada === (encendida === 1),
      `potencial lectura ${clave}: sobre {version, habilitada, items} coherente con la bandera`,
      JSON.stringify(data ?? null).slice(0, 200));
    if (!Array.isArray(data?.items)) continue;
    if (encendida !== 1) {
      check(data.items.length === 0, `potencial lectura ${clave}: bandera apagada → sin ítems`, `${data.items.length} ítems`);
      continue;
    }
    const visibles = await sessions[clave].client.schema('crm').from('leads').select('id').in('id', ids);
    if (visibles.error) {
      fail(`potencial lectura ${clave}: no se pudo leer crm.leads para comparar (${visibles.error.message})`);
      continue;
    }
    const dePuerta = [...new Set(data.items.map((item) => item.lead_id))].sort().join(',');
    const deRls = visibles.data.map((fila) => fila.id).sort().join(',');
    check(dePuerta === deRls, `potencial lectura ${clave}: los ítems son exactamente los leads que su RLS deja ver`,
      `puerta ${data.items.length} vs RLS ${visibles.data.length}`);
  }
  await expectExpectedFailure('potencial lectura vendInactive → 42501 (la baja revoca la lectura)',
    leer(sessions.vendInactive.client), ['42501'], /no autorizado/i);
  await expectExpectedFailure('potencial lectura con 201 ids → 22023',
    leer(sessions.vend1.client, Array.from({ length: 201 }, () => randomUUID())), ['22023'], /m[aá]ximo 200/i);
  // Sin EXECUTE para anon ni service_role.
  const anon = createClient(SUPABASE_URL, ANON_KEY, clientOptions('crm-rls-anon-potencial-lectura'));
  await expectExpectedFailure('potencial lectura anon → 42501 (sin EXECUTE)', leer(anon), ['42501'], DENEGADO);
  await expectExpectedFailure('potencial lectura service_role → 42501 (sin EXECUTE)', leer(admin), ['42501'], DENEGADO);
}

```

## Cuerpos VIVOS del banco (pg_get_functiondef con search_path vacío)

#### private.vendedor_ids_visibles(uuid)
```sql
CREATE OR REPLACE FUNCTION private.vendedor_ids_visibles(p_perfil_id uuid)
 RETURNS SETOF uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$

```
ACL: {postgres=X/postgres,authenticated=X/postgres}

#### private.rol_crm(uuid)
```sql
CREATE OR REPLACE FUNCTION private.rol_crm(p_perfil_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$

```
ACL: {postgres=X/postgres,authenticated=X/postgres}

#### private.es_lector_global()
```sql
CREATE OR REPLACE FUNCTION private.es_lector_global()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$

```
ACL: {postgres=X/postgres,authenticated=X/postgres}

#### private.puede_acceder_crm()
```sql
CREATE OR REPLACE FUNCTION private.puede_acceder_crm()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select private.rol_crm((select auth.uid())) is not null
      or private.es_lector_global();
$function$

```
ACL: {postgres=X/postgres,authenticated=X/postgres}

#### crm.bandera_activa(text)
```sql
CREATE OR REPLACE FUNCTION crm.bandera_activa(p_nombre text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce((select activo from crm.multiempresa_flags where nombre = p_nombre), false)
$function$

```
ACL: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}

#### private.potencial_rechazo(uuid,uuid)
```sql
CREATE OR REPLACE FUNCTION private.potencial_rechazo(p_actor uuid, p_lead_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
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
$function$

```
ACL: {postgres=X/postgres}

#### private.potencial_reloj(uuid,timestamp with time zone,timestamp with time zone)
```sql
CREATE OR REPLACE FUNCTION private.potencial_reloj(p_lead_id uuid, p_marcado_en timestamp with time zone, p_corte timestamp with time zone)
 RETURNS timestamp with time zone
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select greatest(p_marcado_en, coalesce((
    select max(a.creado_en) from crm.actividades a
    where a.lead_id = p_lead_id
      and a.tipo in ('llamada_realizada', 'llamada_no_contestada', 'whatsapp_enviado',
                     'whatsapp_recibido', 'reunion_realizada')
      and a.creado_en <= p_corte), p_marcado_en));
$function$

```
ACL: {postgres=X/postgres}

#### private.dias_lunes_a_sabado(date,date)
```sql
CREATE OR REPLACE FUNCTION private.dias_lunes_a_sabado(p_desde date, p_hasta date)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select coalesce((
    select pg_catalog.count(*)::integer
    from pg_catalog.generate_series((p_desde + 1)::timestamp, (p_hasta - 1)::timestamp, interval '1 day') d
    where pg_catalog.date_part('isodow', d) <> 7
  ), 0);
$function$

```
ACL: {postgres=X/postgres}

#### private.potencial_nivel_tras(crm.nivel_potencial,integer)
```sql
CREATE OR REPLACE FUNCTION private.potencial_nivel_tras(p_nivel crm.nivel_potencial, p_dias integer)
 RETURNS crm.nivel_potencial
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select case
    when p_dias >= 10 then 'frio'::crm.nivel_potencial
    when p_dias >= 5 and p_nivel = 'estrella' then 'tibio'::crm.nivel_potencial
    else p_nivel
  end;
$function$

```
ACL: {postgres=X/postgres}

#### crm.cierres_estado_fn(uuid[])
```sql
CREATE OR REPLACE FUNCTION crm.cierres_estado_fn(p_lead_ids uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid      uuid := (select auth.uid());
  v_rol      text;
  v_lector   boolean;
  v_visibles uuid[];
  v_payload  jsonb;
begin
  v_rol := private.rol_crm(v_uid);
  v_lector := private.es_lector_global();

  -- Guardia de ADMISION, igual que cartera_pagina_fn: quien no es del CRM ni
  -- lector global no pregunta.
  if v_uid is null or (v_rol is null and not v_lector) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  -- El gate RESTRICTIVO de `crm.leads` (`crm_actor_activo_gate`) se INVOCA en
  -- vez de copiarse: una llamada no se desincroniza. Sin esto, un actor
  -- revocado —que la RLS expulsa de la tabla— seguiria leyendo por aqui.
  if not coalesce(private.puede_acceder_crm(), false) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  -- Tope alineado con `cartera_pagina_fn` (p_limite maximo 200): esta funcion
  -- sirve a una pagina en pantalla, no a un volcado.
  if p_lead_ids is not null and array_length(p_lead_ids, 1) > 200 then
    raise exception 'Parametro p_lead_ids invalido: maximo 200'
      using errcode = '22023';
  end if;
  if p_lead_ids is null or array_length(p_lead_ids, 1) is null then
    return '[]'::jsonb;
  end if;

  -- Se resuelve UNA vez (la policy lo evalua como SubPlan en cada fila).
  v_visibles := array(select private.vendedor_ids_visibles(v_uid));

  select coalesce(jsonb_agg(f.fila order by f.lead_id), '[]'::jsonb)
    into v_payload
  from (
    select
      l.id as lead_id,
      jsonb_build_object(
        'lead_id', l.id,
        -- La foto del cierre manda sobre la etapa: si hay fila en
        -- cierres_externos, ese lead cerro en cooperativa, punto.
        'canal', case when ce.lead_id is not null then 'cooperativa' else 'avance' end,
        -- `coalesce` y no un case: los dos canales son excluyentes por
        -- construccion (crm.anular_cierre_avance rechaza un lead con cierre en
        -- cooperativa), asi que como mucho uno de los dos trae fecha.
        'anulado_en', coalesce(ce.anulado_en, ca.anulado_en),
        -- El motivo viaja: la regla de Miguel es que a quien se le quita el
        -- merito merece una razon escrita, no un numero que baja sin explicacion.
        'motivo', coalesce(ce.motivo_anulacion, ca.motivo)
      ) as fila
    from crm.leads l
    -- Los dos son UNIQUE por lead (`cierres_externos_un_cierre_por_lead` y el
    -- unique de `lead_id` en cierres_avance_anulados), asi que ningun join
    -- duplica la fila del lead.
    left join crm.cierres_externos ce on ce.lead_id = l.id and ce.es_cierre_inicial
    left join crm.cierres_avance_anulados ca on ca.lead_id = l.id
    where l.id = any(p_lead_ids)
      -- ── ESPEJO EXACTO de la policy `leads_select` (20260902040000) ─────────
      --   using: activo = true
      --          and ( vendedor_id in (vendedor_ids_visibles(uid))
      --                or (vendedor_id is null and asignado_supervisor_id in (...))
      --                or rol_crm(uid) = 'gerencia'
      --                or es_lector_global() )
      -- 🔴 El `or v_lector` va DENTRO del `activo`, igual que en la policy: el
      -- lector global ve todo lo VIVO y NADA de lo borrado. Hasta el 01/09 iba
      -- fuera —aqui y en la policy— y por eso el Directorio leia el estado de
      -- cierre de leads dados de baja.
      and l.activo = true
      and (
        l.vendedor_id = any(v_visibles)
        -- Lead en la bandeja de un supervisor: sin vendedor todavia.
        -- (`NULL = any(...)` da NULL, no TRUE, asi que la rama de arriba
        -- no se lo lleva por delante.)
        or (l.vendedor_id is null and l.asignado_supervisor_id = any(v_visibles))
        or v_rol = 'gerencia'
        or v_lector
      )
      -- Solo los leads con algo que decir. Un convertido de Avance sano no
      -- viaja: es el caso por defecto del front.
      and (ce.lead_id is not null or ca.lead_id is not null)
  ) f;

  return v_payload;
end;
$function$

```
ACL: {postgres=X/postgres,authenticated=X/postgres}

#### Policies de crm.leads (todas)
```
crm_actor_activo_gate | cmd=* | permisiva=false | roles={authenticated}
  USING ( SELECT private.puede_acceder_crm() AS puede_acceder_crm)
  WITH CHECK ( SELECT private.puede_acceder_crm() AS puede_acceder_crm)
leads_select | cmd=r | permisiva=true | roles={authenticated}
  USING ((activo = true) AND ((vendedor_id IN ( SELECT private.vendedor_ids_visibles(( SELECT auth.uid() AS uid)) AS vendedor_ids_visibles)) OR ((vendedor_id IS NULL) AND (asignado_supervisor_id IN ( SELECT private.vendedor_ids_visibles(( SELECT auth.uid() AS uid)) AS vendedor_ids_visibles))) OR (( SELECT private.rol_crm(( SELECT auth.uid() AS uid)) AS rol_crm) = 'gerencia'::text) OR ( SELECT private.es_lector_global() AS es_lector_global)))
  WITH CHECK (null)
leads_update | cmd=w | permisiva=true | roles={authenticated}
  USING ((activo = true) AND ((private.rol_crm(( SELECT auth.uid() AS uid)) = 'gerencia'::text) OR (vendedor_id IN ( SELECT private.vendedor_ids_visibles(( SELECT auth.uid() AS uid)) AS vendedor_ids_visibles)) OR ((vendedor_id IS NULL) AND (asignado_supervisor_id IN ( SELECT private.vendedor_ids_visibles(( SELECT auth.uid() AS uid)) AS vendedor_ids_visibles)))))
  WITH CHECK (((vendedor_id IS NULL) OR (vendedor_id IN ( SELECT private.vendedor_ids_visibles(( SELECT auth.uid() AS uid)) AS vendedor_ids_visibles))) AND ((asignado_supervisor_id IS NULL) OR (asignado_supervisor_id IN ( SELECT private.vendedor_ids_visibles(( SELECT auth.uid() AS uid)) AS vendedor_ids_visibles))) AND ((activo = true) OR (private.rol_crm(( SELECT auth.uid() AS uid)) = ANY (ARRAY['supervisor'::text, 'gerencia'::text]))))
```
RLS: relrowsecurity=true relforcerowsecurity=false


### Fase 2, la tarea con la que debe coincidir `baja_el` (supabase/migrations/20260930235917_crm_potencial_lead_caducidad.sql)
```sql
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

```
La tarea corre con pg_cron a las 10:10 y 10:40 GMT (05:10 y 05:40 Lima) todos los días: `select private.potencial_caducar()`.
