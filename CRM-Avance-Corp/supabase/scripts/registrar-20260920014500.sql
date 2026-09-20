-- Registra 20260920014500 (crm_actividades_recientes) CON su cuerpo — fail-closed.
-- GENERADO por supabase/scripts/actividades-recientes/generar-registrador.mjs leyendo
-- la migración del archivo: no editar a mano; regenerar. Orden de la casa: PRIMERO
-- aplicar la migración con `db query --linked --file`, DESPUÉS este registrador.
do $reg_recientes$
declare v_n int; v_cuerpo text;
begin
  v_cuerpo := $mig_recientes$-- ACTIVIDAD RECIENTE DEL ÁMBITO — la bitácora de Hoy · Directorio pide al
-- servidor las N gestiones más recientes que el actor puede ver, y el arranque
-- deja de descargar el registro entero de actividades.
--
-- Fase 3 del plan «sin topes» (Miguel, 19/09/2026: «lo que no quiero es que
-- haya esos límites»). Fases 1 (`20260919185718`, historial por lead) y 2
-- (`20260919235100`, tareas por cursor) ya en producción.
--
-- CAUSA, medida en producción el 19/09 (noche): el arranque del CRM sigue
-- llamando a `crm.actividades_del_ambito_fn` (DEFINER, `order by creado_en desc
-- limit 10000`), que PostgREST recorta a 1 000 filas: 13 645 actividades en 365
-- días y 2 886 nuevas por semana, así que un supervisor recibe dos o tres días
-- de historia y la alarma del front (calibrada a 10 000) nunca suena. En sesión
-- real, con el modo SLA `activo` (desde el 07/09), esa lista solo la usa de
-- verdad una pantalla: la bitácora «Actividad reciente» de Hoy · Directorio
-- (8 filas). Las demás la reciben solo para el espejo demo o como respaldo de
-- un reloj que ya sirve la fotografía SLA.
--
-- ── Las cuatro capas (estándar Avanza Digital) ───────────────────────────────
--   1. TABLA    `crm.actividades` — ya existe, log inmutable, RLS
--               `actividades_select`. NO se toca. Índice existente
--               `actividades_recientes_idx (creado_en desc, id)`.
--   2. NÚCLEO   `private.actividades_recientes_core(int)` — las N gestiones
--               más recientes visibles, con el nombre del lead y del autor
--               embebidos. PURO: sin `auth.`, sin autoridad propia,
--               `security invoker`.
--   3. PUERTA   `crm.actividades_recientes_fn(int)` — expuesta a
--               `authenticated`. Valida el INPUT, exige admisión al CRM
--               (42501) y delega.
--   4. PANTALLA Hoy · Directorio («Actividad reciente»). El arranque ya no
--               baja actividades; `crm.actividades_del_ambito_fn` queda en
--               OBSERVACIÓN y se deprecia por migración aparte cuando los
--               logs de PostgREST muestren una semana sin llamadas
--               (CERRAR → OBSERVAR → DERRIBAR).
--
-- POR QUÉ `SECURITY INVOKER`: filas con PII conversacional (el `detalle`). La
-- casa ya decidió (`20260810141953`, y las Fases 1 y 2) que el alcance lo pone
-- la RLS y NO un predicado copiado: la RPC vieja copiaba el predicado y ya se
-- desincronizó una vez (`20260902050000`). Aquí `crm.actividades` se lee bajo
-- `actividades_select` y `crm.leads` bajo `leads_select`. La co-extensividad
-- es ESTRUCTURAL: el `exists (select 1 from crm.leads …)` de
-- `actividades_select` corre él mismo bajo `leads_select`, así que toda
-- gestión visible tiene su lead visible, y `nombre_completo` es NOT NULL. Por
-- eso aquí NO se sella `leads_select` (solo sus grants por columna y su RLS
-- activa): un `lead_nombre` NULL solo podría llegar si `actividades_select`
-- dejara de referenciar `crm.leads`, y eso lo atrapa la huella sellada abajo.
--
-- SELLO COMPARTIDO (auditoría RLS del 19/09): la huella de `actividades_select`
-- la clavan TRES bases: `assert_actividades_de_lead_base()` (Fase 1),
-- `assert_gestion_diaria_registro_base()` (Gestión Diaria F1) y
-- `assert_actividades_recientes_base()` (esta). La migración que cambie esa
-- policy debe, en la MISMA transacción, re-auditar los tres consumidores,
-- reemplazar las tres `_base` con la huella nueva y llamar a los tres gates
-- (y sus mutantes) en el postflight; si no, `test-rls` queda en rojo en tres
-- frentes. Deuda anotada: centralizar el sello en una sola función.
--
-- EL ÚNICO SALTO PRIVILEGIADO ya existe: `private.nombre_de_autor(uuid)` (Fase
-- 1; DEFINER acotado a `crm.equipo` con gate interno). Esta migración solo lo
-- llama; no crea ningún DEFINER nuevo ni toca `public`.
--
-- SIN TOPE GLOBAL NI VENTANA: `p_limite` es el tamaño de la bitácora (1..50),
-- no un recorte del historial. El «hay más» no aplica: es un feed, no una
-- página. Ninguna función usa `count(` ni `sum(1)` (vigía
-- `private.assert_analitica_leads_citas`).
--
-- COORDINADOR: pasa la admisión y recibe `{version:1, items:[]}` (su RLS es ∅
-- por diseño C1), igual que la tabla.
--
-- FORMATO DE FECHAS: `to_jsonb` serializa `timestamptz` con `+00:00` y
-- precisión variable; el front compara por unidades de código, no con
-- `localeCompare` (lección de la Fase 2).
--
-- REVERSIÓN: `drop function crm.actividades_recientes_fn(integer);`
-- `drop function private.actividades_recientes_core(integer);`
-- `drop function private.assert_actividades_recientes();`
-- `drop function private.assert_actividades_recientes_mutantes();`
-- `drop function private.assert_actividades_recientes_base();`. Retirar
-- primero el front (que la llama). Nada de datos que deshacer: solo lee.
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';

-- ── Base del trinquete: lo que TIENE que ser cierto antes y después ──────────
-- Compartida por el preflight y por el gate propio (una sola función para que
-- no diverjan): ayudantes de autoridad y el ayudante del nombre de autor,
-- USAGE/grants de la cadena invoker (incluidos los grants POR COLUMNA de
-- `crm.leads`), RLS ACTIVA en las dos tablas (desactivarla deja las policies
-- en el catálogo sin aplicarse) y `actividades_select` sellada por huella y
-- por conjunto de PERMISIVAS, con la restrictiva del actor activo presente.
-- Sin `count(`.
create function private.assert_actividades_recientes_base() returns text
language plpgsql stable security definer set search_path='' as $function$
declare
  v_huella text;
  v_nombres text[];
begin
  if to_regprocedure('private.puede_acceder_crm()') is null
     or to_regprocedure('private.rol_crm(uuid)') is null
     or to_regprocedure('private.vendedor_ids_visibles(uuid)') is null
     or to_regprocedure('private.es_lector_global()') is null then
    raise exception 'Faltan los ayudantes de autoridad del CRM';
  end if;
  -- La puerta INVOKER llama a la guardia de admision como el actor.
  if not has_function_privilege('authenticated', 'private.puede_acceder_crm()', 'EXECUTE') then
    raise exception 'authenticated no puede ejecutar private.puede_acceder_crm: la puerta fallaria cerrada para todos';
  end if;
  -- El ayudante DEFINER de la Fase 1, con su gate interno (strpos: en LIKE `_` es comodin).
  if not exists (
    select 1 from pg_proc p
    where p.oid = to_regprocedure('private.nombre_de_autor(uuid)')
      and p.prosecdef and strpos(p.prosrc, 'puede_acceder_crm') > 0
  ) then
    raise exception 'Falta private.nombre_de_autor(uuid) con su gate interno (Fase 1)';
  end if;
  -- La cadena puerta (invoker) → núcleo (private) corre como el actor.
  if not has_schema_privilege('authenticated', 'private', 'USAGE') then
    raise exception 'authenticated no tiene USAGE sobre private: la cadena invoker no funcionaria';
  end if;
  if not has_table_privilege('authenticated', 'crm.actividades', 'SELECT') then
    raise exception 'authenticated no puede leer crm.actividades: el nucleo no devolveria nada';
  end if;
  if not has_function_privilege('authenticated', 'private.nombre_de_autor(uuid)', 'EXECUTE') then
    raise exception 'authenticated no puede ejecutar private.nombre_de_autor: la firma de autor fallaria';
  end if;
  -- crm.leads tiene grants POR COLUMNA (regimen del 17/07/2026): las dos que lee el nucleo.
  if not has_column_privilege('authenticated', 'crm.leads', 'id', 'SELECT')
     or not has_column_privilege('authenticated', 'crm.leads', 'nombre_completo', 'SELECT') then
    raise exception 'authenticated no puede leer crm.leads.id/nombre_completo: el nucleo fallaria al embeber el lead';
  end if;
  if not exists (select 1 from pg_class c where c.oid = 'crm.actividades'::regclass and c.relrowsecurity)
     or not exists (select 1 from pg_class c where c.oid = 'crm.leads'::regclass and c.relrowsecurity) then
    raise exception 'RLS desactivada en crm.actividades o crm.leads: la puerta invoker expondria filas ajenas';
  end if;

  -- La policy de lectura de actividades, tal cual se audito el 19/09/2026 (Fase 1).
  select md5(pg_get_expr(pol.polqual, pol.polrelid)) into v_huella
  from pg_policy pol
  where pol.polrelid = 'crm.actividades'::regclass and pol.polname = 'actividades_select';
  if v_huella is distinct from 'e80e3af900b8d9616c28dcd836f1ac94' then
    raise exception 'actividades_select cambio desde la auditoria (md5 %): re-auditar',
      coalesce(v_huella, 'ausente');
  end if;
  select array_agg(pol.polname::text order by pol.polname) into v_nombres
  from pg_policy pol
  where pol.polrelid = 'crm.actividades'::regclass and pol.polpermissive and pol.polcmd in ('r', '*');
  if v_nombres is distinct from array['actividades_select']::text[] then
    raise exception 'crm.actividades tiene otras permisivas de lectura (%): re-auditar quien ve que',
      coalesce(array_to_string(v_nombres, ','), 'ninguna');
  end if;
  if exists (
    select 1 from pg_policy pol
    where pol.polrelid = 'crm.actividades'::regclass and pol.polname = 'actividades_select'
      and pol.polroles is distinct from array['authenticated'::regrole::oid]
  ) then
    raise exception 'actividades_select ya no aplica solo a authenticated';
  end if;
  if not exists (
    select 1 from pg_policy pol
    where pol.polrelid = 'crm.actividades'::regclass and pol.polname = 'crm_actor_activo_gate' and not pol.polpermissive
  ) then
    raise exception 'Falta la restrictiva crm_actor_activo_gate en crm.actividades';
  end if;
  return 'OK: actividades_select sellada por huella y por conjunto, RLS activa, ayudante de autor presente, grants de la cadena invoker presentes';
end;
$function$;
comment on function private.assert_actividades_recientes_base() is
  'Base del trinquete de la actividad reciente: ayudantes de autoridad y nombre_de_autor, USAGE/grants de la cadena invoker (crm.actividades y las columnas id/nombre_completo de crm.leads), RLS activa, y actividades_select sellada por md5 y por conjunto con la restrictiva crm_actor_activo_gate.';
revoke all on function private.assert_actividades_recientes_base()
  from public, anon, authenticated, service_role;

do $preflight$
begin
  perform private.assert_actividades_recientes_base();
  if to_regprocedure('crm.actividades_recientes_fn(integer)') is not null
     or to_regprocedure('private.actividades_recientes_core(integer)') is not null then
    raise exception 'La actividad reciente ya esta instalada';
  end if;
end;
$preflight$;

-- ── CAPA 2 · NÚCLEO ─────────────────────────────────────────────────────────
-- Las N gestiones más recientes que la RLS del actor deja ver, en el orden
-- `(creado_en desc, id asc)` que sirve `actividades_recientes_idx`, con el
-- nombre del lead (bajo `leads_select`, nullable) y la firma del autor.
create function private.actividades_recientes_core(p_limite integer) returns jsonb
language sql
stable
security invoker
set search_path to ''
as $function$
  with recientes as (
    select a.id, a.lead_id, a.tipo, a.detalle, a.creado_por, a.creado_en,
           l.nombre_completo as lead_nombre
    from crm.actividades a
    left join crm.leads l on l.id = a.lead_id
    order by a.creado_en desc, a.id asc
    limit p_limite
  )
  select jsonb_build_object(
    'version', 1,
    'items', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', r.id,
          'lead_id', r.lead_id,
          'lead_nombre', r.lead_nombre,
          'tipo', r.tipo,
          'detalle', r.detalle,
          'autor_nombre', coalesce(private.nombre_de_autor(r.creado_por), '—'),
          'creado_en', r.creado_en
        )
        order by r.creado_en desc, r.id asc
      )
      from recientes r
    ), '[]'::jsonb)
  );
$function$;

comment on function private.actividades_recientes_core(integer) is
  'NÚCLEO: las N gestiones más recientes visibles bajo la RLS del actor (creado_en desc, id asc), con lead_nombre (nullable, bajo leads_select) y autor_nombre (private.nombre_de_autor). Puro: sin auth ni autoridad propia.';

revoke all on function private.actividades_recientes_core(integer)
  from public, anon, authenticated, service_role;
-- Lo llama una puerta INVOKER, así que corre como el actor: necesita EXECUTE.
-- `private` no está expuesto a la API: PostgREST no puede invocarlo directo.
grant execute on function private.actividades_recientes_core(integer) to authenticated;

-- ── CAPA 3 · PUERTA ─────────────────────────────────────────────────────────
create function crm.actividades_recientes_fn(p_limite integer default 8) returns jsonb
language plpgsql
stable
security invoker
set search_path to ''
as $function$
begin
  -- EL INPUT SE VALIDA ANTES DE LEER NADA. Es una bitácora, no una página.
  if p_limite is null or p_limite < 1 or p_limite > 50 then
    raise exception 'Parametro p_limite invalido' using errcode = '22023';
  end if;

  -- Guardia de ADMISIÓN (P04: revocado ≠ ajeno al CRM). El ALCANCE lo pone la
  -- RLS, ver cabecera: aquí no hay predicado de ámbito.
  if not private.puede_acceder_crm() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  return private.actividades_recientes_core(p_limite);
end;
$function$;

comment on function crm.actividades_recientes_fn(integer) is
  'PUERTA: las N (1..50) gestiones más recientes del ámbito con lead_nombre y autor_nombre. SECURITY INVOKER: el alcance lo pone actividades_select; 42501 solo por admisión al CRM. Sin ventana de fecha ni tope global.';

revoke all on function crm.actividades_recientes_fn(integer)
  from public, anon, authenticated, service_role;
grant execute on function crm.actividades_recientes_fn(integer) to authenticated;

-- ── Gate propio ──────────────────────────────────────────────────────────────
create function private.assert_actividades_recientes() returns text
language plpgsql stable security definer set search_path='' as $function$
declare
  v_puerta constant text := 'crm.actividades_recientes_fn(integer)';
  v_nucleo constant text := 'private.actividades_recientes_core(integer)';
  v_firma text;
  v_id oid;
begin
  foreach v_firma in array array[v_puerta, v_nucleo] loop
    v_id := to_regprocedure(v_firma);
    if v_id is null or not exists(
      select 1 from pg_proc p
      where p.oid = v_id and not p.prosecdef
        and p.proowner = 'postgres'::regrole::oid
        and p.provolatile = 's'
        and p.proconfig @> array['search_path=""']
    ) then
      raise exception 'Contrato de la actividad reciente alterado (debe ser INVOKER, stable, search_path vacio): %', v_firma;
    end if;
  end loop;

  -- La guardia de admisión de la puerta, con su FORMA exacta (el nombre suelto
  -- en un comentario no vale). El comportamiento lo clava test-rls.
  v_id := to_regprocedure(v_puerta);
  if not exists(
    select 1 from pg_proc p
    where p.oid = v_id
      and strpos(p.prosrc, 'if not private.puede_acceder_crm() then') > 0
      and strpos(p.prosrc, '42501') > 0
  ) then
    raise exception 'La puerta de la actividad reciente perdio su guardia de admision: %', v_puerta;
  end if;

  -- EXECUTE exactamente para `authenticated`: ni anon, ni service_role, ni PUBLIC.
  foreach v_firma in array array[v_puerta, v_nucleo] loop
    v_id := to_regprocedure(v_firma);
    if not has_function_privilege('authenticated', v_id, 'EXECUTE')
       or exists(
         select 1 from pg_proc p
         cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
         where p.oid = v_id
           and a.grantee not in ('postgres'::regrole::oid, 'authenticated'::regrole::oid)
       ) then
      raise exception 'ACL de la actividad reciente alterado: %', v_firma;
    end if;
  end loop;

  perform private.assert_actividades_recientes_base();

  return 'OK: actividad reciente bajo la RLS, sin predicado copiado, guardia de admision presente y actividades_select sellada';
end;
$function$;
comment on function private.assert_actividades_recientes() is
  'Trinquete de la actividad reciente: puerta y núcleo INVOKER con search_path vacío, guardia de admisión en la puerta, EXECUTE solo para authenticated, y actividades_select sellada por md5 y por conjunto.';
revoke all on function private.assert_actividades_recientes()
  from public, anon, authenticated, service_role;

-- ── Mutantes del trinquete (regla de la casa: por cada defensa, un mutante) ──
-- SOLO PARA EL BANCO. Cada mutante vive en su propia subtransacción y se
-- deshace siempre. Tres desenlaces y solo uno cuenta: DETECTADO (el gate gritó
-- tras aplicarse la mutación); NO DETECTADO (la función falla con su nombre);
-- NO APLICADO (el DDL de la mutación falló: la función falla también, para que
-- un mutante roto nunca se cuente como defensa probada).
create function private.assert_actividades_recientes_mutantes() returns text
language plpgsql volatile security definer set search_path='' as $function$
declare
  v_detectados integer := 0;
  v_mutante text;
  v_nombre text;
  v_ddl text;
  -- «nombre|DDL». Ningún DDL lleva «|».
  v_mutantes constant text[] := array[
    'la puerta pasa a DEFINER|alter function crm.actividades_recientes_fn(integer) security definer',
    'el nucleo pasa a DEFINER|alter function private.actividades_recientes_core(integer) security definer',
    'actividades_select se abre (cambia la huella)|alter policy actividades_select on crm.actividades using (true)',
    'una permisiva NUEVA en crm.actividades|create policy actividades_mutante_recientes on crm.actividades for select to authenticated using (true)',
    'la puerta pierde su guardia de admision|create or replace function crm.actividades_recientes_fn(p_limite integer default 8) returns jsonb language sql stable security invoker set search_path to '''' as $b$ select private.actividades_recientes_core(p_limite) $b$',
    'la puerta conserva el nombre de la guardia solo en un comentario|create or replace function crm.actividades_recientes_fn(p_limite integer default 8) returns jsonb language sql stable security invoker set search_path to '''' as $b$ /* puede_acceder_crm 42501 */ select private.actividades_recientes_core(p_limite) $b$',
    'la puerta se concede a anon|grant execute on function crm.actividades_recientes_fn(integer) to anon',
    'el nucleo se concede a anon|grant execute on function private.actividades_recientes_core(integer) to anon',
    'el nucleo pierde el search_path vacio|alter function private.actividades_recientes_core(integer) reset search_path',
    'el nucleo pasa a VOLATILE|alter function private.actividades_recientes_core(integer) volatile',
    'actividades_select deja de ser solo para authenticated|alter policy actividades_select on crm.actividades to public',
    'desaparece la restrictiva del actor activo|drop policy crm_actor_activo_gate on crm.actividades',
    'authenticated pierde la lectura de crm.actividades|revoke select on table crm.actividades from authenticated',
    'authenticated pierde la lectura de crm.leads (el revoke de TABLA arrastra las columnas; el bloque lo deshace)|revoke select on table crm.leads from authenticated',
    'authenticated pierde USAGE sobre private|revoke usage on schema private from authenticated',
    'authenticated pierde EXECUTE sobre nombre_de_autor|revoke execute on function private.nombre_de_autor(uuid) from authenticated',
    'nombre_de_autor pierde el DEFINER|alter function private.nombre_de_autor(uuid) security invoker',
    'nombre_de_autor pierde su gate interno|create or replace function private.nombre_de_autor(p_id uuid) returns text language sql stable security definer set search_path to '''' as $b$ select p.nombre_completo from public.perfiles p where p.id = p_id $b$',
    'crm.actividades queda sin RLS|alter table crm.actividades disable row level security',
    'crm.leads queda sin RLS|alter table crm.leads disable row level security'
  ];
begin
  foreach v_mutante in array v_mutantes loop
    v_nombre := split_part(v_mutante, '|', 1);
    v_ddl := split_part(v_mutante, '|', 2);
    begin
      execute v_ddl;
      begin
        perform private.assert_actividades_recientes();
      exception when others then
        raise exception 'MUTANTE DETECTADO';
      end;
      raise exception 'MUTANTE NO DETECTADO: % paso el gate', v_nombre;
    exception when others then
      if sqlerrm = 'MUTANTE DETECTADO' then
        v_detectados := v_detectados + 1;
      elsif sqlerrm like 'MUTANTE NO DETECTADO%' then
        raise;
      else
        raise exception 'MUTANTE NO APLICADO (%): %', v_nombre, sqlerrm;
      end if;
    end;
  end loop;
  return format('OK: %s mutantes detectados por private.assert_actividades_recientes()', v_detectados);
end;
$function$;
comment on function private.assert_actividades_recientes_mutantes() is
  'Mutantes del trinquete de la actividad reciente (solo banco): cada mutación vive en una subtransacción que se deshace; distingue detectado / no detectado / no aplicado y falla en los dos últimos.';
revoke all on function private.assert_actividades_recientes_mutantes()
  from public, anon, authenticated, service_role;

do $postflight$
begin
  perform private.assert_actividades_recientes();
  -- Los gates del mundo SLA (que también lee crm.actividades). Los otros
  -- cuatro controles del servidor (auditoría, analítica de leads/citas,
  -- vigencia de analistas y piezas F7) están en ROJO en producción por
  -- trabajos ajenos; llamarlos aquí abortaría una migración que no los
  -- empeora ni los arregla.
  perform private.assert_sla_nucleo();
  perform private.assert_sla_operacion();
  perform private.assert_sla_comandos();
  perform private.assert_sla_avisos();
end;
$postflight$;

notify pgrst, 'reload schema';
commit;
$mig_recientes$;

  -- 1) PIN: lo que la migración hizo ES verdad — puerta, núcleo y gate existen
  --    con la definición publicada (md5 medidos en producción) y el gate propio
  --    responde OK en ESTA base.
  if to_regprocedure('crm.actividades_recientes_fn(integer)') is null
     or to_regprocedure('private.actividades_recientes_core(integer)') is null
     or to_regprocedure('private.assert_actividades_recientes()') is null
     or md5(pg_get_functiondef('crm.actividades_recientes_fn(integer)'::regprocedure)) is distinct from 'a58a58a7288c8431daa7698aa6779fa4'
     or md5(pg_get_functiondef('private.actividades_recientes_core(integer)'::regprocedure)) is distinct from '4689f6bfbfffd07cb105aabd246863e1' then
    raise exception 'registrar actividad reciente: la migración 20260920014500 no está aplicada tal cual — aplicarla antes de registrar';
  end if;
  if private.assert_actividades_recientes() not like 'OK:%' then
    raise exception 'registrar actividad reciente: el gate propio no responde OK';
  end if;

  -- 2) La versión no puede existir con OTRO cuerpo.
  select count(*) into v_n from supabase_migrations.schema_migrations
   where version = '20260920014500' and statements is not null
     and (cardinality(statements) <> 1 or statements[1] <> v_cuerpo);
  if v_n > 0 then
    raise exception 'registrar actividad reciente: la versión 20260920014500 existe con OTRO cuerpo — investigar antes de tocar';
  end if;

  -- 3) Registro (idempotente).
  insert into supabase_migrations.schema_migrations (version, name, statements)
  values ('20260920014500', 'crm_actividades_recientes', array[v_cuerpo])
  on conflict (version) do nothing;

  -- 4) RELECTURA fail-closed: la fila EXACTA, o se cae la transacción entera.
  select count(*) into v_n from supabase_migrations.schema_migrations
   where version = '20260920014500' and name = 'crm_actividades_recientes'
     and cardinality(statements) = 1 and statements[1] = v_cuerpo;
  if v_n <> 1 then
    raise exception 'registrar actividad reciente: la relectura no encontró la fila exacta';
  end if;
end $reg_recientes$;
