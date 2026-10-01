ROLE: SECONDARY_REVIEWER.

Do not modify files.
Do not implement the task.
Do not invoke Claude.
Do not delegate to another coding agent.
Do not create another review chain.

Segunda ronda (LEVEL 3) sobre la migración `20260930002929_crm_sla_resumen_solo_operativos` que ya revisaste
(encargo `2026-09-30-codex-sla-resumen-operativos.md`, CHANGES_REQUESTED con P2 «la ruta "ya aplicada" acepta un
ayudante sin validar y omite el guardián»). Comprueba que quedó cerrado y refuta lo nuevo. Sin base ni red.
Responde con VERDICT, SUMMARY, FINDINGS P0–P3 con evidencia, RISKS / TEST GAPS, NEXT ACTIONS, CONFIDENCE.

## Evidencia nueva
- **P2 cerrado.** La ruta «ya aplicada» de la migración ahora exige los invariantes del ayudante (dueño postgres,
  ACL exacta `{postgres=X/postgres}` no nula, INVOKER, STABLE, search_path vacío), su huella
  `md5(pg_get_functiondef)` = `8d478d783e4c591662388ddf7405058a` (medida en la base: incluye el salto de línea
  final que añade Postgres) y ejecuta `private.assert_sla_avisos()` antes de `return`. El postflight normal
  también exige la huella del ayudante. La reversa ejecuta el guardián también en su ruta idempotente. El
  registrador exige huella e invariantes del ayudante además de las del adaptador.
- **Negativos ensayados en producción (transacción deshecha):** tras aplicar, (NEG1) se sustituyó el cuerpo del
  ayudante por `select '{}'::uuid[]` y se repitió la migración → rechazada: «PREFLIGHT (ya aplicada): el
  ayudante no tiene la huella esperada (dde61ef9…)»; (NEG2) con el ayudante correcto se le concedió EXECUTE a
  `authenticated` y se repitió → rechazada: «PREFLIGHT (ya aplicada): el ayudante no tiene los invariantes
  esperados (dueño postgres, acl {postgres=X/postgres,authenticated=X/postgres} …)». Luego reversa (adaptador
  vivo, sin ayudante, guardián OK) → migración → registrador (2 sentencias). Después del rollback: huella viva
  7b5f75df…, sin ayudante, 0 registros.
- **Oráculo ampliado a 5 actores** (gerencia, supervisor con bandeja, 2 analistas, **coordinador**): md5 del
  resumen sin `calculado_en` + controles `estado_sla_leads_v2_fn(5 ids)` y `cola_accion_v3_fn()`: **15/15
  iguales**; guardián OK. Tiempos: gerencia 1.761 → 1.146 ms, supervisor 815 → 617, analistas 107–123 → 117–118,
  coordinador 11 → 24 (el ayudante se evalúa aunque el núcleo no le devuelva filas). Lector global/directorio: 0
  perfiles activos, no ejercitable con actor real; su recorte sigue en el núcleo, no en el ayudante.
- **R1, correspondencia de etapas:** `private.sla_hechos_actuales` devuelve
  `TABLE(lead_id uuid, etapa_actual text, vendedor_id uuid, supervisor_id uuid, creado_en timestamp with time zone, ciclo_n integer, ciclo_inicio timestamp with time zone, asignacion_id uuid, asignacion_inicio timestamp with time zone, etapa_sla_id uuid, etapa_inicio timestamp with time zone, limite_original timestamp with time zone, politica_etapa_id uuid, base jsonb, activo boolean, asignacion_coherente boolean, etapa_coherente boolean, nombre_completo text, analista_nombre text)`
  — su segunda columna es `l.etapa` de `crm.leads`; `sla_operacion_leads` calcula `v_terminal` sobre
  `h.etapa_actual` con las mismas cuatro etapas que filtra el ayudante. Metadatos del paquete: en
  `sla_operacion_autorizada`, `'modo',v_control.modo,'control_revision',v_control.revision,'calculado_en',v_ahora,
  'primera_activacion_en',v_control.primera_activacion_en,'activacion_hipotetica_en',case when
  v_control.primera_activacion_en is null and v_control.modo='observacion' then v_ahora end` — todos de
  `crm.sla_operacion_control` y del reloj, no de las filas.
- Registro: `registrar.sql` es un script aparte que corre DESPUÉS del commit de la migración (patrón de la casa:
  `db query --file` no registra); no hay atomicidad entre ambos y así está documentado en el ledger.

## Migración completa (versión final)
```sql
-- ============================================================================
-- Resumen de avisos SLA: el adaptador evalúa solo las oportunidades que pueden avisar
-- (crm.avisos_sla_resumen_v2_fn + private.sla_leads_operativos)
-- ============================================================================
-- Paso 4 · fase 1 del refactor por módulos, aprobado por Miguel el 29/09/2026 («DALE»).
-- Nota del vault: «CRM - perfil de carga lectura vs escritura (2026-09-29)».
--
-- Problema medido (29/09, producción, como gerencia): el resumen tarda 1.735–1.749 ms y es la puerta
-- que más tiempo total consume (9.540 llamadas en 4 días). Pide al núcleo TODAS las oportunidades
-- activas (2.583) con `sla_operacion_autorizada(null,true)`: el núcleo evalúa una a una la regla
-- completa y arma su ficha, y el resumen solo cuenta. 1.139 de esas 2.583 están descartadas o
-- convertidas: son «lead_terminal» en `private.sla_operacion_leads` y nunca producen avisos ni
-- «pendientes», así que no aportan nada a las cuatro cifras ni a `proximo_cambio_en`.
--
-- Cambio: el adaptador pasa al núcleo solo los ids de las oportunidades activas en etapa comercial
-- (`private.sla_leads_operativos()`, las mismas cuatro etapas no terminales del núcleo). El núcleo,
-- su autoridad, su reloj y las demás puertas que lo usan NO cambian. El ayudante vive en `private`
-- porque `assert_sla_avisos` prohíbe a los adaptadores `crm.*` leer `crm.leads`; es INVOKER (solo lo
-- llama este adaptador DEFINER, así corre como postgres) y sin ejecutores de la API.
--
-- Prototipo medido en producción (deshecho): resumen IDÉNTICO para gerencia, supervisor con bandeja y
-- dos analistas; gerencia 1.749 → 1.196 ms, supervisor 800 → 629 ms (filas evaluadas 2.583 → 1.444).
--
-- Huellas (md5 de pg_get_functiondef): adaptador vivo 7b5f75dfb6ac3e480659bdef3dc5ac0f → nuevo e9ce617ab0cc33bc5614ef69e877cc71; ayudante 8d478d783e4c591662388ddf7405058a.
-- Idempotente y fail-closed; al final ejecuta private.assert_sla_avisos() (que llama a assert_sla_nucleo):
-- si el guardián del SLA no está conforme, la transacción se deshace.
-- Reversa: supabase/scripts/sla-resumen-operativos/reversa.sql (restaura el adaptador vivo, retira el
-- ayudante y vuelve a pasar el guardián; conserva la fila de schema_migrations).

begin;
set local lock_timeout = '10s';

do $mig$
declare
  v_md5 text; v_oid oid := 'crm.avisos_sla_resumen_v2_fn()'::regprocedure;
  v_owner text; v_acl text; v_secdef boolean; v_vol "char"; v_cfg text[];
  h_owner text; h_acl text; h_secdef boolean; h_vol "char"; h_cfg text[];
begin
  select md5(pg_get_functiondef(v_oid)), pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into v_md5, v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = v_oid;
  -- Invariantes del adaptador que la huella NO cubre: dueño, ACL exacta (postgres + authenticated, que exige
  -- assert_sla_avisos), DEFINER, STABLE y search_path vacío (se guarda como search_path=""). IS NOT TRUE: un NULL rechaza.
  if (v_owner = 'postgres' and v_acl is not null and v_acl = '{postgres=X/postgres,authenticated=X/postgres}' and v_secdef is true and v_vol = 's'
    and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'PREFLIGHT: dueño/ACL/definer/volatilidad/search_path del adaptador vivo no son los esperados (dueño %, acl %, definer %, vol %, cfg %)', v_owner, v_acl, v_secdef, v_vol, v_cfg;
  end if;
  if v_md5 = 'e9ce617ab0cc33bc5614ef69e877cc71' and to_regprocedure('private.sla_leads_operativos()') is not null then
    -- Ruta «ya aplicada» (Codex r1 P2): exige los MISMOS invariantes y la huella del ayudante, y pasa el
    -- guardián, antes de dar la migración por hecha. Que exista el ayudante no prueba que sea el esperado.
  select pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into h_owner, h_acl, h_secdef, h_vol, h_cfg from pg_proc p where p.oid = 'private.sla_leads_operativos()'::regprocedure;
    if (h_owner = 'postgres' and h_acl is not null and h_acl = '{postgres=X/postgres}' and h_secdef is false and h_vol = 's'
    and exists (select 1 from unnest(h_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
      raise exception 'PREFLIGHT (ya aplicada): el ayudante no tiene los invariantes esperados (dueño %, acl %, definer %, vol %, cfg %)', h_owner, h_acl, h_secdef, h_vol, h_cfg;
    end if;
    if md5(pg_get_functiondef('private.sla_leads_operativos()'::regprocedure)) <> '8d478d783e4c591662388ddf7405058a' then
      raise exception 'PREFLIGHT (ya aplicada): el ayudante no tiene la huella esperada (%)', md5(pg_get_functiondef('private.sla_leads_operativos()'::regprocedure));
    end if;
    raise notice 'assert_sla_avisos: %', private.assert_sla_avisos();
    raise notice 'sla_resumen_solo_operativos: ya aplicada (huella %)', v_md5;
    return;
  end if;
  if v_md5 <> '7b5f75dfb6ac3e480659bdef3dc5ac0f' then
    raise exception 'PREFLIGHT: crm.avisos_sla_resumen_v2_fn() no es el cuerpo vivo del 29/09/2026 (huella %)', v_md5;
  end if;

  -- 1) el ayudante (idempotente)
  execute $def$
CREATE OR REPLACE FUNCTION private.sla_leads_operativos()
 RETURNS uuid[]
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  -- Ids de las oportunidades activas en etapa comercial: las mismas cuatro etapas que
  -- private.sla_operacion_leads considera NO terminales (v_terminal). Sin PII; el núcleo
  -- aplica después su propia visibilidad por actor. Nunca NULL: vacío = '{}'.
  select coalesce(array_agg(l.id order by l.id), '{}'::uuid[])
  from crm.leads l
  where l.activo is true
    and l.etapa in ('nuevo','contactado','reunion_agendada','propuesta_enviada');
$function$
$def$;
  execute 'revoke all on function private.sla_leads_operativos() from public, anon, authenticated, service_role';
  execute $c$comment on function private.sla_leads_operativos() is 'Ids de las oportunidades activas en etapa comercial (las cuatro etapas no terminales de private.sla_operacion_leads). Solo para adaptadores del núcleo SLA que cuentan avisos: el núcleo aplica después su propia visibilidad. Sin PII; vacío = {}.'$c$;
  select pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into h_owner, h_acl, h_secdef, h_vol, h_cfg from pg_proc p where p.oid = 'private.sla_leads_operativos()'::regprocedure;
  if (h_owner = 'postgres' and h_acl is not null and h_acl = '{postgres=X/postgres}' and h_secdef is false and h_vol = 's'
    and exists (select 1 from unnest(h_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'POSTFLIGHT: el ayudante no quedó como se esperaba (dueño %, acl %, definer %, vol %, cfg %)', h_owner, h_acl, h_secdef, h_vol, h_cfg;
  end if;
  if md5(pg_get_functiondef('private.sla_leads_operativos()'::regprocedure)) <> '8d478d783e4c591662388ddf7405058a' then
    raise exception 'POSTFLIGHT: huella inesperada del ayudante (%)', md5(pg_get_functiondef('private.sla_leads_operativos()'::regprocedure));
  end if;

  -- 2) el adaptador
  execute $def$
CREATE OR REPLACE FUNCTION crm.avisos_sla_resumen_v2_fn()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_datos jsonb;v_total integer;v_avisos integer;v_criticas integer;v_grupos jsonb;
begin
  -- Misma ventana autorizada y mismo instante que ficha y cola. El conteo
  -- incluye toda la cartera visible, sin depender del lote local ni pagina.
  -- Solo las oportunidades que pueden avisar: activas y en etapa comercial (las descartadas y
  -- convertidas son «lead_terminal» en el núcleo y nunca producen avisos ni «pendientes»; 1.139 de
  -- 2.583 el 29/09/2026). El núcleo, su autoridad y su reloj no cambian; el ayudante vive en
  -- private porque este adaptador no puede leer hechos crudos (assert_sla_avisos).
  v_datos:=private.sla_operacion_autorizada(private.sla_leads_operativos(),true);
  with filas as materialized (
    select f.value from jsonb_array_elements(v_datos->'filas') f
    where v_datos->>'modo'='activo' and (f.value#>>'{senales,pendientes}')::boolean
  ), avisos as materialized (
    select a.value from filas f cross join lateral jsonb_array_elements(f.value#>'{estado,avisos}') a
  ), grupos as (
    select a.value->>'bucket' as bucket,count(*) as total,
      min((a.value->>'prioridad')::integer) as prioridad
    from avisos a group by a.value->>'bucket'
  )
  select (select count(*) from filas),(select count(*) from avisos),
    (select count(*) from avisos a where a.value->>'severidad'='critica'),
    coalesce((select jsonb_agg(jsonb_build_object('bucket',g.bucket,'total',g.total) order by g.prioridad) from grupos g),'[]'::jsonb)
  into v_total,v_avisos,v_criticas,v_grupos;
  return (v_datos-'filas'-'contexto_ambito')||jsonb_build_object(
    'total_oportunidades',v_total,'total_avisos',v_avisos,'criticas',v_criticas,'grupos',v_grupos);
end;
$function$
$def$;
  select md5(pg_get_functiondef(v_oid)), pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into v_md5, v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = v_oid;
  if v_md5 <> 'e9ce617ab0cc33bc5614ef69e877cc71' then
    raise exception 'POSTFLIGHT: huella inesperada del adaptador tras el cambio (%)', v_md5;
  end if;
  if (v_owner = 'postgres' and v_acl is not null and v_acl = '{postgres=X/postgres,authenticated=X/postgres}' and v_secdef is true and v_vol = 's'
    and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'POSTFLIGHT: dueño, ACL, definer, volatilidad o search_path del adaptador cambiaron (dueño %, acl %, definer %, vol %, cfg %)', v_owner, v_acl, v_secdef, v_vol, v_cfg;
  end if;

  -- 3) el guardián del SLA tiene la última palabra
  raise notice 'assert_sla_avisos: %', private.assert_sla_avisos();
  raise notice 'sla_resumen_solo_operativos: aplicada (huella %)', v_md5;
end $mig$;

commit;
```

## Reversa (versión final; el bloque `$def$` es el adaptador vivo)
```sql
-- REVERSA de 20260930002929_crm_sla_resumen_solo_operativos: restaura el adaptador VIVO del 29/09/2026 tal cual, retira el ayudante y vuelve a pasar el
-- guardián del SLA. Se niega si el adaptador no tiene la huella nueva o sus invariantes. NO toca schema_migrations
-- (anotarlo en MIGRACIONES.md el mismo día).
begin;
set local lock_timeout = '10s';
do $rev$
declare
  v_md5 text; v_oid oid := 'crm.avisos_sla_resumen_v2_fn()'::regprocedure;
  v_owner text; v_acl text; v_secdef boolean; v_vol "char"; v_cfg text[];
  h_owner text; h_acl text; h_secdef boolean; h_vol "char"; h_cfg text[];
begin
  select md5(pg_get_functiondef(v_oid)), pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into v_md5, v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = v_oid;
  -- Invariantes del adaptador que la huella NO cubre: dueño, ACL exacta (postgres + authenticated, que exige
  -- assert_sla_avisos), DEFINER, STABLE y search_path vacío (se guarda como search_path=""). IS NOT TRUE: un NULL rechaza.
  if (v_owner = 'postgres' and v_acl is not null and v_acl = '{postgres=X/postgres,authenticated=X/postgres}' and v_secdef is true and v_vol = 's'
    and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'REVERSA: invariantes del adaptador incorrectos (dueño %, acl %, definer %, vol %, cfg %); no se toca', v_owner, v_acl, v_secdef, v_vol, v_cfg;
  end if;
  if v_md5 = '7b5f75dfb6ac3e480659bdef3dc5ac0f' and to_regprocedure('private.sla_leads_operativos()') is null then
    raise notice 'assert_sla_avisos: %', private.assert_sla_avisos();
    raise notice 'REVERSA: ya está el adaptador vivo del 29/09 (%)', v_md5; return;
  end if;
  if v_md5 <> 'e9ce617ab0cc33bc5614ef69e877cc71' then raise exception 'REVERSA: huella desconocida del adaptador (%), no se toca', v_md5; end if;
  execute $def$
<adaptador vivo completo>
$def$;
  execute 'drop function if exists private.sla_leads_operativos()';
  select md5(pg_get_functiondef(v_oid)), pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into v_md5, v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = v_oid;
  if v_md5 <> '7b5f75dfb6ac3e480659bdef3dc5ac0f' then raise exception 'REVERSA: la huella restaurada no coincide (%)', v_md5; end if;
  if (v_owner = 'postgres' and v_acl is not null and v_acl = '{postgres=X/postgres,authenticated=X/postgres}' and v_secdef is true and v_vol = 's'
    and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'REVERSA: tras restaurar, invariantes del adaptador incorrectos (dueño %, acl %, definer %, vol %, cfg %)', v_owner, v_acl, v_secdef, v_vol, v_cfg;
  end if;
  raise notice 'assert_sla_avisos: %', private.assert_sla_avisos();
  raise notice 'REVERSA_SLA_RESUMEN_OK (%)', v_md5;
end $rev$;
commit;

```

## Registrador (versión final; los bloques `$stm$` son el ayudante y el adaptador nuevos)
```sql
-- REGISTRO en supabase_migrations.schema_migrations de 20260930002929_crm_sla_resumen_solo_operativos.
-- Correr DESPUÉS de aplicar. Idempotente; se niega si el adaptador no tiene la huella nueva o sus invariantes,
-- si falta el ayudante, o si la versión ya está registrada con otro nombre; relee la fila antes de confirmar.
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_sla_resumen_solo_operativos'));
do $chk$
declare
  v_md5 text; v_oid oid := 'crm.avisos_sla_resumen_v2_fn()'::regprocedure;
  v_owner text; v_acl text; v_secdef boolean; v_vol "char"; v_cfg text[];
  h_owner text; h_acl text; h_secdef boolean; h_vol "char"; h_cfg text[];
begin
  select md5(pg_get_functiondef(v_oid)), pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into v_md5, v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = v_oid;
  if v_md5 <> 'e9ce617ab0cc33bc5614ef69e877cc71' then
    raise exception 'REGISTRO: el adaptador no tiene la huella nueva (%); aplica primero la migración 20260930002929', v_md5;
  end if;
  -- Invariantes del adaptador que la huella NO cubre: dueño, ACL exacta (postgres + authenticated, que exige
  -- assert_sla_avisos), DEFINER, STABLE y search_path vacío (se guarda como search_path=""). IS NOT TRUE: un NULL rechaza.
  if (v_owner = 'postgres' and v_acl is not null and v_acl = '{postgres=X/postgres,authenticated=X/postgres}' and v_secdef is true and v_vol = 's'
    and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'REGISTRO: invariantes del adaptador incorrectos (dueño %, acl %, definer %, vol %, cfg %); no se registra', v_owner, v_acl, v_secdef, v_vol, v_cfg;
  end if;
  if to_regprocedure('private.sla_leads_operativos()') is null then raise exception 'REGISTRO: falta private.sla_leads_operativos()'; end if;
  select pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into h_owner, h_acl, h_secdef, h_vol, h_cfg from pg_proc p where p.oid = 'private.sla_leads_operativos()'::regprocedure;
  if (h_owner = 'postgres' and h_acl is not null and h_acl = '{postgres=X/postgres}' and h_secdef is false and h_vol = 's'
    and exists (select 1 from unnest(h_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'REGISTRO: invariantes del ayudante incorrectos (dueño %, acl %, definer %, vol %, cfg %); no se registra', h_owner, h_acl, h_secdef, h_vol, h_cfg;
  end if;
  if md5(pg_get_functiondef('private.sla_leads_operativos()'::regprocedure)) <> '8d478d783e4c591662388ddf7405058a' then
    raise exception 'REGISTRO: el ayudante no tiene la huella esperada (%); no se registra', md5(pg_get_functiondef('private.sla_leads_operativos()'::regprocedure));
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations
             where version = '20260930002929' and coalesce(name,'') <> 'crm_sla_resumen_solo_operativos') then
    raise exception 'REGISTRO: la versión 20260930002929 ya está registrada con otro nombre';
  end if;
end $chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20260930002929', 'crm_sla_resumen_solo_operativos', array[$stm$
<definición>
$stm$, $stm$
<definición>
$stm$])
on conflict (version) do nothing;
do $post$
begin
  if not exists (select 1 from supabase_migrations.schema_migrations
                 where version = '20260930002929' and name = 'crm_sla_resumen_solo_operativos') then
    raise exception 'REGISTRO: tras el insert, la versión 20260930002929 no quedó con el nombre esperado';
  end if;
  raise notice 'REGISTRO_SLA_RESUMEN_OK';
end $post$;
select version, name from supabase_migrations.schema_migrations where version = '20260930002929';
commit;

```

## Qué refutar
1. ¿Queda cerrado el P2 en las tres piezas? ¿Alguna ruta sigue confirmando sin verificar?
2. ¿Los negativos NEG1/NEG2 prueban lo que dicen? ¿Falta algún negativo proporcionado (p. ej. adaptador con otra ACL)?
3. Con la correspondencia de etapas y los metadatos transcritos, ¿queda algún hueco en la equivalencia?
