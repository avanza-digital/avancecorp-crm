-- Registra 20260919235100 (crm_tareas_pendientes_keyset) CON su cuerpo — fail-closed.
-- GENERADO por supabase/scripts/tareas-pendientes/generar-registrador.mjs leyendo
-- la migración del archivo: no editar a mano; regenerar. Orden de la casa: PRIMERO
-- aplicar la migración con `db query --linked --file`, DESPUÉS este registrador.
do $reg_tareas$
declare v_n int; v_cuerpo text;
begin
  v_cuerpo := $mig_tareas$-- TAREAS SIN TOPE — la agenda pide las tareas pendientes del ámbito por
-- cursor, completas, por una puerta de la capa 3.
--
-- Fase 2 del plan «sin topes» (Miguel, 19/09/2026: «lo que no quiero es que
-- haya esos límites»). La Fase 1 (`20260919185718`) arregló el historial por
-- lead; esta arregla el mismo defecto de clase en las tareas.
--
-- CAUSA, medida en producción el 19/09 (noche): el front pide las tareas
-- pendientes del ámbito en UNA llamada directa a la tabla (`from('tareas')…
-- limit 2000`, orden `vence_en asc, id asc`). PostgREST recorta cada respuesta
-- a 1 000 filas (`max_rows`), así que el `limit 2000` nunca actúa y la alarma
-- del front (calibrada a 2 000) nunca suena. Gerencia tiene 1 156 pendientes:
-- YA PIERDE 156, las de vencimiento más lejano (Agenda mes/semana, Citas de
-- gerencia, alertas de vencidas). Los supervisores (699 y 457) cruzan el corte
-- en semanas: se crean 1 236 tareas por semana. Además la pantalla leía la
-- tabla directo: uno de los saltos de capa anotados en el plan de cierre
-- (Etapa 1, foco 2).
--
-- ── Las cuatro capas (estándar Avanza Digital) ───────────────────────────────
--   1. TABLA    `crm.tareas` — ya existe, RLS `tareas_select`. NO se toca
--               salvo por UN índice parcial nuevo (abajo).
--   2. NÚCLEO   `private.tareas_pendientes_core(int,timestamptz,uuid)` — una
--               página keyset `(vence_en asc, id asc)` de las tareas
--               pendientes visibles, con el nombre y la etapa del lead
--               embebidos. PURO: sin `auth.`, sin autoridad propia,
--               `security invoker`.
--   3. PUERTA   `crm.tareas_pendientes_fn(int,timestamptz,uuid)` — expuesta a
--               `authenticated`. Valida el INPUT, exige admisión al CRM
--               (42501) y delega.
--   4. PANTALLA `listarTareasDelAmbito` (Agenda, Hoy, Citas de gerencia,
--               cerrar tarea, ficha) pide lotes de 500 hasta que no hay más.
--               La agenda de postventa sigue por su puerta (`postventa_agenda_fn`).
--
-- POR QUÉ `SECURITY INVOKER`, SIN PREDICADO COPIADO: la puerta devuelve
-- exactamente lo que la RLS ya le muestra a cada actor en la tabla — ni una
-- fila más ni una menos (`test-rls` lo clava por rol). No hay ningún predicado
-- de ámbito copiado en la puerta ni en el núcleo: la casa ya pagó una vez la
-- desincronización de un predicado copiado (`20260902050000`), y aquí no hay
-- nada que desincronizar. Se descartó la «pista de ámbito» que el plan
-- contemplaba para aprovechar un índice por vendedor: medido en producción
-- bajo sesión real (`set role authenticated` + `request.jwt.claims`), la
-- lectura sin pista tarda 15 ms para un analista (90 filas visibles de 1 164
-- pendientes) y 13 ms para gerencia (1 156 filas). Un predicado copiado por
-- ahorrar milisegundos que nadie nota sería la semilla del próximo desfase.
--
-- EL ÍNDICE: `tareas_pendientes_keyset_idx (vence_en, id) where estado =
-- 'pendiente' and activo` da al planificador el orden del cursor sobre las
-- pendientes (hoy 1 160 de 5 067 filas) para que cada página termine en
-- cuanto reúne su lote en vez de ordenar todo lo visible. Es rendimiento, no
-- seguridad: no forma parte del gate.
--
-- `lead_nombre` y `lead_etapa` viajan en cada tarea (`left join crm.leads`
-- bajo `leads_select`) para que la Fase 4 deje a la agenda sin depender de
-- la foto de leads. Son NULLABLE a propósito: `tareas_select` mira columnas
-- de la tarea, no del lead, y existe un camino real en que la tarea es
-- visible y el lead no (`20260910150039` re-apunta tareas por
-- `inversionista_id`). Hoy en producción: 0 pendientes con lead borrado.
-- `crm.leads` tiene grants POR COLUMNA: el preflight comprueba las tres que
-- el núcleo lee (`id`, `nombre_completo`, `etapa`) con `has_column_privilege`.
--
-- QUÉ FILAS: las mismas que la pantalla pedía — `estado = 'pendiente' and
-- activo and (lead_id is not null or perfil_id is not null)`. Las 4 pendientes
-- ancladas solo a `inversionista_id` las sirve `postventa_agenda_fn` y el
-- front las fusiona por id, como hoy.
--
-- KEYSET EN FORMA DE TUPLA: `(vence_en, id) > (p_despues_de, p_despues_id)`.
-- Los dos sentidos son ASC, así que la comparación de fila es legal e
-- indexable (la cartera keyset explica lo contrario para su caso MIXTO). Los
-- empates de `vence_en` son reales (112 vencimientos compartidos hoy): el
-- desempate por `id` es parte del cursor, no un adorno.
--
-- «HAY MÁS» sin `count(`: el front pide `limite + 1` (mismo contrato que el
-- historial y la cartera). Por eso el tope de `p_limite` es 1 000 y no 500:
-- el lote del front es 500 y pide 501. El payload es UN jsonb (una sola fila
-- para PostgREST): `max_rows` no lo recorta.
--
-- VIGÍA DE CONTADORES CRUDOS (`private.assert_analitica_leads_citas`): ninguna
-- función de esta migración usa `count(` ni `sum(1)`.
--
-- COORDINADOR: pasa la admisión al CRM y recibe `{version:1, items:[]}` —
-- su RLS sobre tareas es ∅ por diseño C1 (`20260721120000`). Es lo mismo que
-- la tabla le respondía; no es una denegación.
--
-- FORMATO DE FECHAS: `to_jsonb` serializa `timestamptz` igual que PostgREST
-- (`2026-09-19T20:00:00+00:00`, siempre con el mismo desplazamiento y con
-- precisión variable). En ese formato el orden por UNIDADES DE CÓDIGO es el
-- cronológico; el front fusiona con postventa comparando así, no con
-- `localeCompare` (cuya colación pone «.» antes que «+» y desordenaba
-- `…:00.001+00:00` frente a `…:00+00:00`; revisión de Codex del 19/09).
--
-- REVERSIÓN: `drop function crm.tareas_pendientes_fn(integer,timestamptz,uuid);`
-- `drop function private.tareas_pendientes_core(integer,timestamptz,uuid);`
-- `drop function private.assert_tareas_pendientes();`
-- `drop function private.assert_tareas_pendientes_mutantes();`
-- `drop function private.assert_tareas_pendientes_base();`
-- `drop index crm.tareas_pendientes_keyset_idx;`. Retirar primero el front
-- (que la llama): vuelve a la lectura directa con su recorte. Nada de datos
-- que deshacer: esta migración solo lee.
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';

-- ── Base del trinquete: lo que TIENE que ser cierto antes y después ──────────
-- Comprobaciones compartidas por el preflight y por el gate propio (una sola
-- función para que no diverjan): ayudantes de autoridad, USAGE/grants de la
-- cadena invoker (incluidos los grants POR COLUMNA de `crm.leads`), y la
-- policy de lectura de tareas sellada por huella Y por conjunto de PERMISIVAS
-- (una permisiva nueva no cambia el md5 de la vieja pero sí amplía quién ve
-- qué; una restrictiva nueva —como la de postventa, `tareas_postventa_lectura`,
-- posterior a la versión del banco— solo puede restar, y la puerta la hereda
-- sola por ser invoker: no se sella). La restrictiva del actor activo sí debe
-- seguir presente. Sin `count(`: la vigía de contadores crudos marcaría una
-- función que mencione `crm.leads` y cuente.
create function private.assert_tareas_pendientes_base() returns text
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
  -- La cadena puerta (invoker) → núcleo (private) corre como el actor.
  if not has_schema_privilege('authenticated', 'private', 'USAGE') then
    raise exception 'authenticated no tiene USAGE sobre private: la cadena invoker no funcionaria';
  end if;
  if not has_table_privilege('authenticated', 'crm.tareas', 'SELECT') then
    raise exception 'authenticated no puede leer crm.tareas: el nucleo no devolveria nada';
  end if;
  -- Las policies solo cuentan si la RLS esta ACTIVA: desactivarla las deja en el
  -- catalogo sin aplicarse, y una puerta invoker expondria filas ajenas
  -- (revision de Codex del 19/09).
  if not exists (select 1 from pg_class c where c.oid = 'crm.tareas'::regclass and c.relrowsecurity)
     or not exists (select 1 from pg_class c where c.oid = 'crm.leads'::regclass and c.relrowsecurity) then
    raise exception 'RLS desactivada en crm.tareas o crm.leads: la puerta invoker expondria filas ajenas';
  end if;
  -- crm.leads tiene grants POR COLUMNA (regimen del 17/07/2026, CLAUDE.md del
  -- subproyecto): las tres que lee el nucleo, comprobadas una a una.
  if not has_column_privilege('authenticated', 'crm.leads', 'id', 'SELECT')
     or not has_column_privilege('authenticated', 'crm.leads', 'nombre_completo', 'SELECT')
     or not has_column_privilege('authenticated', 'crm.leads', 'etapa', 'SELECT') then
    raise exception 'authenticated no puede leer crm.leads.id/nombre_completo/etapa: el nucleo fallaria al embeber el lead';
  end if;

  -- La policy de lectura de tareas, tal cual se auditó el 19/09/2026.
  select md5(pg_get_expr(pol.polqual, pol.polrelid)) into v_huella
  from pg_policy pol
  where pol.polrelid = 'crm.tareas'::regclass and pol.polname = 'tareas_select';
  if v_huella is distinct from '073deaeb5700bac14209ec795b71567e' then
    raise exception 'tareas_select cambio desde la auditoria (md5 %): re-auditar',
      coalesce(v_huella, 'ausente');
  end if;

  -- El CONJUNTO de permisivas de lectura: exactamente una, solo para
  -- authenticated; y las dos restrictivas que acotan la lectura, presentes.
  select array_agg(pol.polname::text order by pol.polname) into v_nombres
  from pg_policy pol
  where pol.polrelid = 'crm.tareas'::regclass and pol.polpermissive and pol.polcmd in ('r', '*');
  if v_nombres is distinct from array['tareas_select']::text[] then
    raise exception 'crm.tareas tiene otras permisivas de lectura (%): re-auditar quien ve que',
      coalesce(array_to_string(v_nombres, ','), 'ninguna');
  end if;
  if exists (
    select 1 from pg_policy pol
    where pol.polrelid = 'crm.tareas'::regclass and pol.polname = 'tareas_select'
      and pol.polroles is distinct from array['authenticated'::regrole::oid]
  ) then
    raise exception 'tareas_select ya no aplica solo a authenticated';
  end if;
  if not exists (
    select 1 from pg_policy pol
    where pol.polrelid = 'crm.tareas'::regclass and pol.polname = 'crm_actor_activo_gate' and not pol.polpermissive
  ) then
    raise exception 'Falta la restrictiva crm_actor_activo_gate en crm.tareas';
  end if;
  return 'OK: tareas_select sellada por huella y por conjunto, restrictiva del actor activo presente, grants de la cadena invoker presentes';
end;
$function$;
comment on function private.assert_tareas_pendientes_base() is
  'Base del trinquete de las tareas por cursor: ayudantes de autoridad, USAGE/grants de la cadena invoker (crm.tareas y las columnas id/nombre_completo/etapa de crm.leads), y tareas_select sellada por md5 y por conjunto de permisivas, con la restrictiva crm_actor_activo_gate presente.';
revoke all on function private.assert_tareas_pendientes_base()
  from public, anon, authenticated, service_role;

do $preflight$
begin
  perform private.assert_tareas_pendientes_base();
  if to_regprocedure('crm.tareas_pendientes_fn(integer,timestamptz,uuid)') is not null
     or to_regprocedure('private.tareas_pendientes_core(integer,timestamptz,uuid)') is not null
     or to_regclass('crm.tareas_pendientes_keyset_idx') is not null then
    raise exception 'Las tareas por cursor ya estan instaladas';
  end if;
end;
$preflight$;

-- ── CAPA 1 · el índice del cursor ───────────────────────────────────────────
-- Parcial sobre las pendientes vivas, en el orden exacto del keyset. 5 067
-- filas hoy: se construye en milisegundos dentro de la transacción.
create index tareas_pendientes_keyset_idx on crm.tareas (vence_en, id)
  where estado = 'pendiente' and activo;
comment on index crm.tareas_pendientes_keyset_idx is
  'Orden del cursor (vence_en, id) de las tareas pendientes vivas para crm.tareas_pendientes_fn. Rendimiento, no seguridad.';

-- ── CAPA 2 · NÚCLEO ─────────────────────────────────────────────────────────
-- Una página keyset `(vence_en asc, id asc)` de las tareas pendientes que la
-- RLS del actor deja ver, con el lead embebido (nullable). `security invoker`:
-- se ejecuta bajo `tareas_select` y `leads_select`; no interpreta autenticación
-- ni autoridad. Las columnas son exactamente las que la pantalla pedía
-- (`COLUMNAS_TAREA`) más `lead_nombre` y `lead_etapa`.
create function private.tareas_pendientes_core(
  p_limite integer,
  p_despues_de timestamptz,
  p_despues_id uuid
) returns jsonb
language sql
stable
security invoker
set search_path to ''
as $function$
  with pagina as (
    select
      t.id, t.lead_id, t.perfil_id, t.vendedor_id, t.asignado_supervisor_id,
      t.tipo, t.titulo, t.nota, t.vence_en, t.duracion_min, t.estado,
      t.modalidad_reunion, t.ubicacion_reunion, t.enlace_reunion,
      t.resultado_reunion, t.motivo_no_realizada, t.detalle_cierre_reunion,
      t.confirmada_en, t.reagendada_de, t.reprogramaciones, t.activo, t.creado_en,
      l.nombre_completo as lead_nombre,
      l.etapa as lead_etapa
    from crm.tareas t
    left join crm.leads l on l.id = t.lead_id
    where t.estado = 'pendiente'
      and t.activo
      and (t.lead_id is not null or t.perfil_id is not null)
      and (p_despues_de is null or (t.vence_en, t.id) > (p_despues_de, p_despues_id))
    order by t.vence_en asc, t.id asc
    limit p_limite
  )
  select jsonb_build_object(
    'version', 1,
    'items', coalesce((
      select jsonb_agg(to_jsonb(pg) order by pg.vence_en asc, pg.id asc)
      from pagina pg
    ), '[]'::jsonb)
  );
$function$;

comment on function private.tareas_pendientes_core(integer, timestamptz, uuid) is
  'NÚCLEO: página keyset (vence_en asc, id asc) de las tareas pendientes vivas ancladas a un lead o a un perfil, bajo la RLS del actor, con lead_nombre/lead_etapa embebidos (nullable). Puro: sin auth ni autoridad propia.';

revoke all on function private.tareas_pendientes_core(integer, timestamptz, uuid)
  from public, anon, authenticated, service_role;
-- Lo llama una puerta INVOKER, así que corre como el actor: necesita EXECUTE.
-- `private` no está expuesto a la API: PostgREST no puede invocarlo directo.
grant execute on function private.tareas_pendientes_core(integer, timestamptz, uuid)
  to authenticated;

-- ── CAPA 3 · PUERTA ─────────────────────────────────────────────────────────
create function crm.tareas_pendientes_fn(
  p_limite integer default 500,
  p_despues_de timestamptz default null,
  p_despues_id uuid default null
) returns jsonb
language plpgsql
stable
security invoker
set search_path to ''
as $function$
begin
  -- EL INPUT SE VALIDA ANTES DE LEER NADA. Tope 1 000: el front pide 500 + 1.
  if p_limite is null or p_limite < 1 or p_limite > 1000 then
    raise exception 'Parametro p_limite invalido' using errcode = '22023';
  end if;
  -- Cursor A MEDIAS = páginas que se saltan filas en silencio. O los dos
  -- componentes o ninguno: el desempate por id es parte del cursor.
  if (p_despues_de is null) <> (p_despues_id is null) then
    raise exception 'Cursor incompleto: p_despues_de y p_despues_id viajan juntos'
      using errcode = '22023';
  end if;

  -- Guardia de ADMISIÓN (P04: revocado ≠ ajeno al CRM). El ALCANCE lo pone la
  -- RLS, ver cabecera: aquí no hay predicado de ámbito.
  if not private.puede_acceder_crm() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  return private.tareas_pendientes_core(p_limite, p_despues_de, p_despues_id);
end;
$function$;

comment on function crm.tareas_pendientes_fn(integer, timestamptz, uuid) is
  'PUERTA: tareas pendientes del ámbito por cursor keyset (vence_en asc, id asc), lotes de hasta 1 000, con lead_nombre/lead_etapa. SECURITY INVOKER: el alcance lo pone tareas_select; 42501 solo por admisión al CRM. Sin tope global.';

revoke all on function crm.tareas_pendientes_fn(integer, timestamptz, uuid)
  from public, anon, authenticated, service_role;
grant execute on function crm.tareas_pendientes_fn(integer, timestamptz, uuid)
  to authenticated;

-- ── Gate propio ──────────────────────────────────────────────────────────────
-- Trinquete: puerta y núcleo siguen siendo INVOKER (el alcance es de la RLS),
-- estables y con search_path vacío; la puerta conserva su guardia de admisión;
-- las dos funciones exponen EXECUTE exactamente a `authenticated`; y la policy
-- de la que depende el diseño sigue siendo la auditada.
create function private.assert_tareas_pendientes() returns text
language plpgsql stable security definer set search_path='' as $function$
declare
  v_puerta constant text := 'crm.tareas_pendientes_fn(integer,timestamptz,uuid)';
  v_nucleo constant text := 'private.tareas_pendientes_core(integer,timestamptz,uuid)';
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
      raise exception 'Contrato de las tareas por cursor alterado (debe ser INVOKER, stable, search_path vacio): %', v_firma;
    end if;
  end loop;

  -- La guardia de admisión de la puerta, con su FORMA exacta (`if not
  -- private.puede_acceder_crm() then` + 42501): el nombre suelto en un
  -- comentario o en una condición inalcanzable no vale. strpos, no LIKE: el
  -- nombre lleva guiones bajos y en LIKE `_` es comodín. El comportamiento
  -- (42501 real para un revocado) lo clava test-rls, no este trinquete.
  v_id := to_regprocedure(v_puerta);
  if not exists(
    select 1 from pg_proc p
    where p.oid = v_id
      and strpos(p.prosrc, 'if not private.puede_acceder_crm() then') > 0
      and strpos(p.prosrc, '42501') > 0
  ) then
    raise exception 'La puerta de las tareas por cursor perdio su guardia de admision: %', v_puerta;
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
      raise exception 'ACL de las tareas por cursor alterado: %', v_firma;
    end if;
  end loop;

  -- La policy y los grants de la cadena invoker: la base lo grita si alguien
  -- los toca.
  perform private.assert_tareas_pendientes_base();

  return 'OK: tareas por cursor bajo la RLS, sin predicado copiado, guardia de admision presente y tareas_select sellada';
end;
$function$;
comment on function private.assert_tareas_pendientes() is
  'Trinquete de las tareas por cursor: puerta y núcleo INVOKER con search_path vacío, guardia de admisión en la puerta, EXECUTE solo para authenticated, y tareas_select sellada por md5 y por conjunto.';
revoke all on function private.assert_tareas_pendientes()
  from public, anon, authenticated, service_role;

-- ── Mutantes del trinquete (regla de la casa: por cada defensa, un mutante) ──
-- SOLO PARA EL BANCO (lo llama test-rls por la vía fuera de banda). Cada
-- mutante vive en su propia subtransacción: se aplica la mutación, se llama al
-- gate y —grite o no— la subtransacción se deshace. Tres desenlaces y solo uno
-- cuenta: DETECTADO (el gate gritó DESPUÉS de aplicarse la mutación);
-- NO DETECTADO (la mutación pasó el gate: la función falla con su nombre);
-- NO APLICADO (la mutación misma falló, p. ej. un DDL mal escrito: la función
-- falla también, para que un mutante roto nunca se cuente como defensa probada;
-- revisión de Codex del 19/09). Nunca deja el esquema alterado.
create function private.assert_tareas_pendientes_mutantes() returns text
language plpgsql volatile security definer set search_path='' as $function$
declare
  v_detectados integer := 0;
  v_mutante text;
  v_nombre text;
  v_ddl text;
  -- «nombre|DDL». Ningún DDL lleva «|».
  v_mutantes constant text[] := array[
    'la puerta pasa a DEFINER|alter function crm.tareas_pendientes_fn(integer, timestamptz, uuid) security definer',
    'el nucleo pasa a DEFINER|alter function private.tareas_pendientes_core(integer, timestamptz, uuid) security definer',
    'tareas_select se abre (cambia la huella)|alter policy tareas_select on crm.tareas using (true)',
    'una permisiva NUEVA en crm.tareas (la huella de la vieja no cambia)|create policy tareas_mutante_cursor on crm.tareas for select to authenticated using (true)',
    'la puerta pierde su guardia de admision|create or replace function crm.tareas_pendientes_fn(p_limite integer default 500, p_despues_de timestamptz default null, p_despues_id uuid default null) returns jsonb language sql stable security invoker set search_path to '''' as $b$ select private.tareas_pendientes_core(p_limite, p_despues_de, p_despues_id) $b$',
    'la puerta conserva el nombre de la guardia solo en un comentario|create or replace function crm.tareas_pendientes_fn(p_limite integer default 500, p_despues_de timestamptz default null, p_despues_id uuid default null) returns jsonb language sql stable security invoker set search_path to '''' as $b$ /* puede_acceder_crm 42501 */ select private.tareas_pendientes_core(p_limite, p_despues_de, p_despues_id) $b$',
    'la puerta se concede a anon|grant execute on function crm.tareas_pendientes_fn(integer, timestamptz, uuid) to anon',
    'el nucleo se concede a anon|grant execute on function private.tareas_pendientes_core(integer, timestamptz, uuid) to anon',
    'el nucleo pierde el search_path vacio|alter function private.tareas_pendientes_core(integer, timestamptz, uuid) reset search_path',
    'el nucleo pasa a VOLATILE|alter function private.tareas_pendientes_core(integer, timestamptz, uuid) volatile',
    'tareas_select deja de ser solo para authenticated|alter policy tareas_select on crm.tareas to public',
    'desaparece la restrictiva del actor activo|drop policy crm_actor_activo_gate on crm.tareas',
    'authenticated pierde la lectura de crm.leads (el revoke de TABLA arrastra las columnas; el bloque lo deshace)|revoke select on table crm.leads from authenticated',
    'authenticated pierde la lectura de crm.tareas|revoke select on table crm.tareas from authenticated',
    'authenticated pierde USAGE sobre private|revoke usage on schema private from authenticated',
    'crm.tareas queda sin RLS (las policies siguen ahi pero no se aplican)|alter table crm.tareas disable row level security',
    'crm.leads queda sin RLS|alter table crm.leads disable row level security'
  ];
begin
  foreach v_mutante in array v_mutantes loop
    v_nombre := split_part(v_mutante, '|', 1);
    v_ddl := split_part(v_mutante, '|', 2);
    begin
      execute v_ddl;
      begin
        perform private.assert_tareas_pendientes();
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
  return format('OK: %s mutantes detectados por private.assert_tareas_pendientes()', v_detectados);
end;
$function$;
comment on function private.assert_tareas_pendientes_mutantes() is
  'Mutantes del trinquete de las tareas por cursor (solo banco): cada mutación vive en una subtransacción que se deshace; distingue detectado / no detectado / no aplicado y falla en los dos últimos.';
revoke all on function private.assert_tareas_pendientes_mutantes()
  from public, anon, authenticated, service_role;

do $postflight$
begin
  perform private.assert_tareas_pendientes();
  if not exists (
    select 1 from pg_index i
    where i.indexrelid = 'crm.tareas_pendientes_keyset_idx'::regclass and i.indisvalid and i.indpred is not null
  ) then
    raise exception 'El indice del cursor no quedo valido';
  end if;
  -- Los gates del mundo SLA (que también lee crm.tareas). Los otros cuatro
  -- controles del servidor (auditoría, analítica de leads/citas, vigencia de
  -- analistas y piezas F7) están en ROJO en producción desde antes de este
  -- cambio y por trabajos ajenos a él; llamarlos aquí abortaría una migración
  -- que no los empeora ni los arregla.
  perform private.assert_sla_nucleo();
  perform private.assert_sla_operacion();
  perform private.assert_sla_comandos();
  perform private.assert_sla_avisos();
end;
$postflight$;

notify pgrst, 'reload schema';
commit;
$mig_tareas$;

  -- 1) PIN: lo que la migración hizo ES verdad — puerta, núcleo, gate e índice
  --    existen con la definición publicada (md5 medidos en producción) y el
  --    gate propio responde OK en ESTA base.
  if to_regprocedure('crm.tareas_pendientes_fn(integer,timestamptz,uuid)') is null
     or to_regprocedure('private.tareas_pendientes_core(integer,timestamptz,uuid)') is null
     or to_regprocedure('private.assert_tareas_pendientes()') is null
     or to_regclass('crm.tareas_pendientes_keyset_idx') is null
     or md5(pg_get_functiondef('crm.tareas_pendientes_fn(integer,timestamptz,uuid)'::regprocedure)) is distinct from '5edd699559108383a0e44a90b51d9ad6'
     or md5(pg_get_functiondef('private.tareas_pendientes_core(integer,timestamptz,uuid)'::regprocedure)) is distinct from '6c7b921a01e4e81f6a76c7b8f5154421' then
    raise exception 'registrar tareas por cursor: la migración 20260919235100 no está aplicada tal cual — aplicarla antes de registrar';
  end if;
  if private.assert_tareas_pendientes() not like 'OK:%' then
    raise exception 'registrar tareas por cursor: el gate propio no responde OK';
  end if;

  -- 2) La versión no puede existir con OTRO cuerpo.
  select count(*) into v_n from supabase_migrations.schema_migrations
   where version = '20260919235100' and statements is not null
     and (cardinality(statements) <> 1 or statements[1] <> v_cuerpo);
  if v_n > 0 then
    raise exception 'registrar tareas por cursor: la versión 20260919235100 existe con OTRO cuerpo — investigar antes de tocar';
  end if;

  -- 3) Registro (idempotente).
  insert into supabase_migrations.schema_migrations (version, name, statements)
  values ('20260919235100', 'crm_tareas_pendientes_keyset', array[v_cuerpo])
  on conflict (version) do nothing;

  -- 4) RELECTURA fail-closed: la fila EXACTA, o se cae la transacción entera.
  select count(*) into v_n from supabase_migrations.schema_migrations
   where version = '20260919235100' and name = 'crm_tareas_pendientes_keyset'
     and cardinality(statements) = 1 and statements[1] = v_cuerpo;
  if v_n <> 1 then
    raise exception 'registrar tareas por cursor: la relectura no encontró la fila exacta';
  end if;
end $reg_tareas$;
