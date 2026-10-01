-- ============================================================================
-- Cartera F5: la canónica de cada persona y el analista atribuido de cada contrato se calculan
-- UNA vez por llamada, no por fila (private.cartera_f5_fuentes)
-- ============================================================================
-- Refactor por módulos, aprobado por Miguel el 30/09/2026 (objetivo fijado con /goal tras el plan por fases).
-- Nota del vault: «CRM - auditoria de indices (2026-09-30)». Ensayos: supabase/scripts/ensayo-cartera-f5-fuentes-mapas/.
--
-- Problema medido en producción (30/09, `track_functions` en transacción deshecha): la ficha de inversionista
-- (crm.inversionista_ficha_fn, 490–535 ms, 1.575 llamadas en 4 días) calcula la cartera entera
-- (private.cartera_f5_fuentes, 726 fuentes) SIETE veces por llamada = 291 ms; y cada cálculo llama por FILA a
-- private.inversionista_canonica() (~1.900 veces, CTE recursiva) y a private.analista_atribuido_cadena()
-- (~685 veces, CTE recursiva): 13.408 + 4.795 llamadas por ficha (218 + 123 ms). Hoy 0 personas tienen padre
-- (inversionista_canonico_id) y operaciones_cartera tiene 3 filas.
--
-- Cambio: el MISMO cuerpo, con dos mapas jsonb calculados una vez por llamada (`canon_map`: id → canónica con el
-- mismo paseo hacia la raíz, tope 16, y sin raíz el propio id; `atrib_map`: contrato → analista del primer ancestro
-- «upgrade» por operaciones_cartera, con visitados y tope 100) leídos con `->>`. La cadena es LINEAL porque
-- operaciones_cartera.contrato_nuevo_id es UNIQUE (20260824231133): no puede haber dos ancestros «upgrade» al mismo
-- nivel (Codex r1 P2 refutado con esa evidencia). inversionista_canonica y analista_atribuido_cadena NO cambian; el
-- preflight exige sus huellas del 30/09 (si cambian, revisar los mapas; Codex r1 P2 aceptado).
-- Medido: 42 → 11 ms por llamada, 726/726 filas con el mismo md5;
-- punta a punta (reemplazo deshecho): 33/33 salidas idénticas (29 fichas, agenda, estado, cartera, postventa_estado);
-- ficha 509 → 284 ms, agenda de postventa 164 → 97, cartera de inversionistas 193 → 126, estado 52 → 19.
-- Nada más cambia: misma firma, STABLE, SECURITY DEFINER (como estaba), search_path vacío, dueño y ACL.
-- Ninguna puerta ni el front cambian; la nombran 11 funciones (9 DEFINER y 2 INVOKER, incluida la envoltura
-- cartera_f5_fuentes_reales): ficha, gestion, documento, personas_visibles, listar, estado, postventa_fuente,
-- postventa_vencimientos, metricas_f7_fuentes, trg_piloto_f8_control_validar y la envoltura.
--
-- Huellas (md5 de pg_get_functiondef, medidas en la base): viva 94fa33cfcca657f70a1a94f98c3bf482 → nueva fa15f7765d0892c790c7a4b6822e756e.
-- Idempotente y fail-closed. Reversa: supabase/scripts/cartera-f5-fuentes-mapas/reversa.sql (restaura el cuerpo
-- vivo del 30/09 tal cual; conserva la fila de schema_migrations: anotarlo en el ledger).

begin;
-- REPEATABLE READ: las dos lecturas del oráculo ven el mismo snapshot (auditor-rls P3-1); sin él, un commit ajeno entre
-- ambas daría un falso POSTFLIGHT (fail-closed, sin daño, pero obligaría a reintentar).
set transaction isolation level repeatable read;
set local lock_timeout = '10s';

do $mig$
declare
  v_md5 text; v_oid oid := 'private.cartera_f5_fuentes()'::regprocedure;
  v_owner text; v_acl text; v_secdef boolean; v_vol "char"; v_cfg text[];
  v_antes text; v_despues text; v_n_antes int; v_n_despues int;
begin
  select md5(pg_get_functiondef(v_oid)), pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into v_md5, v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = v_oid;
  -- Invariantes que la huella NO cubre: dueño, ACL (nunca NULL), SECURITY DEFINER (así estaba y así sigue), STABLE y
  -- search_path vacío (se guarda como search_path="", con comillas). Se evalúa con IS NOT TRUE para que un NULL también rechace.
  if (v_owner = 'postgres' and v_acl is not null and v_acl = '{postgres=X/postgres}' and v_secdef is true and v_vol = 's'
    and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'PREFLIGHT: dueño/ACL/definer/volatilidad/search_path de la función no son los esperados (dueño %, acl %, definer %, vol %, cfg %)', v_owner, v_acl, v_secdef, v_vol, v_cfg;
  end if;
  -- Las dos funciones cuyo criterio copian los mapas deben ser las del 30/09/2026 (Codex P2): si cambian, hay que revisar
  -- los mapas antes de aplicar o registrar. Se evalúa con IS NOT TRUE para que un NULL (función ausente) también rechace.
  if ((select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = to_regprocedure('private.inversionista_canonica(uuid)')) = '34702897135078893b7d3a726b0c1816'
      and (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = to_regprocedure('private.analista_atribuido_cadena(uuid)')) = '3c9cec305b014ad8c933df25057d3e8b') is not true then
    raise exception 'PREFLIGHT: private.inversionista_canonica(uuid) o private.analista_atribuido_cadena(uuid) no son las del 30/09/2026 (huellas esperadas 34702897135078893b7d3a726b0c1816 y 3c9cec305b014ad8c933df25057d3e8b); revisar los mapas de cartera_f5_fuentes antes de seguir';
  end if;
  if v_md5 = 'fa15f7765d0892c790c7a4b6822e756e' then
    raise notice 'crm_cartera_f5_fuentes_mapas: ya aplicada (huella %)', v_md5;
    return;
  end if;
  if v_md5 <> '94fa33cfcca657f70a1a94f98c3bf482' then
    raise exception 'PREFLIGHT: private.cartera_f5_fuentes() no es el cuerpo vivo del 30/09/2026 (huella %)', v_md5;
  end if;
  -- Oráculo dentro de la misma transacción: las MISMAS filas (texto de la fila, con multiplicidad, en orden estable)
  -- antes y después; si difieren, se deshace todo.
  select count(*), md5(coalesce(string_agg(f::text, '|' order by f::text), '')) into v_n_antes, v_antes from private.cartera_f5_fuentes() f;

  execute $def$
CREATE OR REPLACE FUNCTION private.cartera_f5_fuentes()
 RETURNS TABLE(fuente_id uuid, inversionista_id uuid, inversion_id uuid, empresa text, perfil_id uuid, lead_id uuid, numero text, capital numeric, moneda text, estado text, fecha_comercial date, fecha_imputacion date, vence_en date, analista_origen_id uuid, es_inicial boolean, es_demo boolean, identidad_coherente boolean, creado_en timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- La canónica de cada persona y el analista atribuido de cada contrato se calculan UNA vez por
  -- llamada (mapas jsonb) en vez de una CTE recursiva por FILA: medido el 30/09/2026, cada llamada
  -- hacía ~1.900 llamadas a inversionista_canonica() y ~685 a analista_atribuido_cadena() (42 ms);
  -- con los mapas, 11 ms y las mismas 726 filas. Los mapas repiten el criterio EXACTO de esas dos
  -- funciones (que no cambian): paseo hacia la raíz con tope 16 y, sin raíz, el propio id; primer
  -- ancestro «upgrade» por operaciones_cartera con lista de visitados y tope 100.
  with recursive
  paseo as (
    select i.id as origen, i.id, i.inversionista_canonico_id, 1 as n from crm.inversionistas i
    union all
    select w.origen, i.id, i.inversionista_canonico_id, w.n+1
    from paseo w join crm.inversionistas i on i.id = w.inversionista_canonico_id where w.n < 16
  ),
  canon as (
    select origen as id,
      coalesce((array_agg(id order by n desc) filter (where inversionista_canonico_id is null))[1], origen) as canon
    from paseo group by origen
  ),
  cadena as (
    select c.id as raiz, c.id as contrato_id, 0 as nivel, array[c.id] as visitados from public.contratos c
    union all
    select cd.raiz, o.contrato_origen_id, cd.nivel + 1, cd.visitados || o.contrato_origen_id
    from cadena cd join crm.operaciones_cartera o on o.contrato_nuevo_id = cd.contrato_id
    where o.contrato_origen_id is not null and not (o.contrato_origen_id = any(cd.visitados)) and cd.nivel < 100
  ),
  atrib as (
    select distinct on (cd.raiz) cd.raiz, con.analista_cierre_id
    from cadena cd join public.contratos con on con.id = cd.contrato_id
    where con.categoria = 'upgrade' order by cd.raiz, cd.nivel asc
  ),
  canon_map as (select coalesce(jsonb_object_agg(id::text, canon::text), '{}'::jsonb) as m from canon),
  atrib_map as (select coalesce(jsonb_object_agg(raiz::text, analista_cierre_id::text), '{}'::jsonb) as m from atrib)
  select c.id, ids.personas[1], iv.id, 'avance'::text, c.cliente_id, null::uuid,
    c.numero_contrato, c.capital, c.moneda, c.estado,
    c.fecha_cierre_comercial, c.fecha_cierre_comercial, c.fecha_vencimiento,
    coalesce((((select m from atrib_map)->>c.id::text)::uuid),c.analista_cierre_id),
    iv.es_primera_conversion,c.es_demo,
    cardinality(ids.personas)=1, c.creado_en
  from public.contratos c
  left join crm.inversiones iv on iv.contrato_id=c.id
  cross join lateral (
    select array_agg(distinct coalesce(((select m from canon_map)->>x.id::text)::uuid, x.id)) as personas
    from (
      select i.id from crm.inversionistas i where i.perfil_id=c.cliente_id
      union select iv.inversionista_id where iv.inversionista_id is not null
    ) x
  ) ids
  union all
  select ce.id, ids.personas[1],iv.id,ce.cooperativa,null::uuid,ce.lead_id,
    ce.referencia_externa,ce.monto,ce.moneda,
    case when ce.anulado_en is not null then 'anulado_comercialmente'
      when ce.vence_en < (statement_timestamp() at time zone 'America/Lima')::date
      then 'vencido' else 'vigente' end,
    coalesce(ce.fecha_comercial,(ce.creado_en at time zone 'America/Lima')::date),
    coalesce(ce.fecha_imputacion,(ce.creado_en at time zone 'America/Lima')::date),
    ce.vence_en,ce.vendedor_id,ce.es_cierre_inicial,
    ce.id='a112aead-184a-4979-9041-943978fadae4'::uuid,
    cardinality(ids.personas)=1,ce.creado_en
  from crm.cierres_externos ce
  left join crm.inversiones iv on iv.cierre_externo_id=ce.id
  left join crm.leads l on l.id=ce.lead_id
  cross join lateral (
    select array_agg(distinct coalesce(((select m from canon_map)->>x.id::text)::uuid, x.id)) as personas
    from (select ce.inversionista_id as id union select iv.inversionista_id
          union select l.inversionista_id) x where x.id is not null
  ) ids;
$function$
$def$;

  select count(*), md5(coalesce(string_agg(f::text, '|' order by f::text), '')) into v_n_despues, v_despues from private.cartera_f5_fuentes() f;
  if v_n_antes <> v_n_despues or v_antes <> v_despues then
    raise exception 'POSTFLIGHT: la cartera cambió de forma (antes % filas md5 %, después % filas md5 %); se deshace', v_n_antes, v_antes, v_n_despues, v_despues;
  end if;
  select md5(pg_get_functiondef(v_oid)), pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into v_md5, v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = v_oid;
  if v_md5 <> 'fa15f7765d0892c790c7a4b6822e756e' then
    raise exception 'POSTFLIGHT: huella inesperada tras el cambio (%)', v_md5;
  end if;
  -- Invariantes que la huella NO cubre: dueño, ACL (nunca NULL), SECURITY DEFINER (así estaba y así sigue), STABLE y
  -- search_path vacío (se guarda como search_path="", con comillas). Se evalúa con IS NOT TRUE para que un NULL también rechace.
  if (v_owner = 'postgres' and v_acl is not null and v_acl = '{postgres=X/postgres}' and v_secdef is true and v_vol = 's'
    and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'POSTFLIGHT: dueño/ACL/definer/volatilidad/search_path de la función no son los esperados (dueño %, acl %, definer %, vol %, cfg %)', v_owner, v_acl, v_secdef, v_vol, v_cfg;
  end if;
  raise notice 'crm_cartera_f5_fuentes_mapas: aplicada (huella %, % fuentes idénticas)', v_md5, v_n_despues;
end $mig$;

comment on function private.cartera_f5_fuentes() is
  'Cartera F5: una fila por fuente (contrato Avance o cierre externo) con su persona canónica y su analista atribuido. '
  'Canónica y atribución se calculan una vez por llamada (mapas jsonb) con el mismo criterio que inversionista_canonica y '
  'analista_atribuido_cadena (30/09/2026). SECURITY DEFINER: solo la llaman funciones de private/crm.';

commit;
