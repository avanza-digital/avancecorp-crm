-- Registra 20260919185718 (crm_actividades_de_lead) CON su cuerpo — fail-closed.
-- GENERADO por supabase/scripts/historial-lead/generar-registrador.mjs leyendo
-- la migración del archivo: no editar a mano; regenerar. Orden de la casa: PRIMERO
-- aplicar la migración con `db query --linked --file`, DESPUÉS este registrador.
do $reg_historial$
declare v_n int; v_cuerpo text;
begin
  v_cuerpo := $mig_historial$-- HISTORIAL POR LEAD — la ficha pide el historial de ESE lead, completo e
-- igual para todos los roles.
--
-- Pedido de Miguel (2026-09-19): «el historial de seguimientos no está
-- sincronizado entre analista, supervisor y gerencia: a un analista le sale un
-- seguimiento y al supervisor solo "Lead creado"». Y después: «lo que no
-- quiero es que haya esos límites».
--
-- CAUSA, medida en producción el 19/09: el front descarga TODAS las
-- actividades del ámbito con `crm.actividades_del_ambito_fn` (sin parámetros,
-- `order by creado_en desc limit 10000`) y filtra por lead en el navegador.
-- PostgREST recorta cada respuesta a 1 000 filas (`max_rows`), así que el
-- `limit 10000` nunca actúa: un analista recibe meses de historial (sus 1 000
-- filas más recientes), un supervisor con 10 analistas recibe ~4 días
-- (8 016 actividades en 365 d; la fila 1 000 era del 15/09) y gerencia ~2
-- días (13 626; la fila 1 000, del 17/09). «Lead creado» no es una actividad:
-- es un ítem fijo del front, y verlo solo significa cero filas para ese lead.
-- El recorte era MUDO porque la alarma del front comparaba contra 10 000.
--
-- ── Las cuatro capas (estándar Avanza Digital) ───────────────────────────────
--   1. TABLA    `crm.actividades` — ya existe, log inmutable, RLS
--               `actividades_select`. NO se toca.
--   2. NÚCLEO   `private.actividades_de_lead_core(uuid,int,timestamptz,uuid)`
--               — la lectura: una página keyset del historial de UN lead más
--               las tres señales «alguna vez» que el pipeline necesita. PURO:
--               sin `auth.`, sin autoridad propia, `security invoker`.
--   3. PUERTA   `crm.actividades_de_lead_fn(uuid,int,timestamptz,uuid)` —
--               expuesta a `authenticated`. Valida el INPUT, exige admisión al
--               CRM, exige que el lead sea VISIBLE (42501 explícito) y delega.
--   4. PANTALLA la ficha del lead (`Timeline`), «Descartar» y «Cerrar tarea»,
--               que dejan de filtrar la lista global y piden esto por lead.
--
-- POR QUÉ `SECURITY INVOKER` (y no el DEFINER de la RPC vieja): esta función
-- devuelve FILAS con PII conversacional (el `detalle` de cada llamada). La
-- casa ya decidió para ese caso (`20260810141953`, F2 tramo 1): el alcance lo
-- pone la RLS y NO un predicado copiado. `actividades_select` es co-extensiva
-- con `leads_select` —quien ve el lead ve todas sus actividades, certificado
-- allí mismo— y la RPC vieja, DEFINER con predicado copiado, ya se
-- desincronizó una vez de la policy (`20260902050000`). Aquí no hay nada que
-- desincronizar: `crm.actividades` se lee bajo su propia policy y la
-- denegación explícita sale de un `exists` sobre `crm.leads` bajo
-- `leads_select`. Las huellas de las dos policies se sellan abajo: el diseño
-- descansa en que sigan siendo co-extensivas.
--
-- EL ÚNICO SALTO PRIVILEGIADO: el nombre del autor. La policy de
-- `public.perfiles` solo deja a `authenticated` leer su propia fila, así que
-- una lectura invoker pintaría «—» en toda gestión ajena (hoy la ficha muestra
-- el nombre). `private.nombre_de_autor(uuid)` es `security definer`, acotado a
-- miembros de `crm.equipo` (históricos incluidos: un autor revocado sigue
-- firmando lo que escribió) y concedido a `authenticated` — el mismo patrón
-- que `private.cliente_ficha_autorizada_fn` bajo `crm.cliente_ficha_fn`
-- (`20260829183627`). Esta migración solo LEE `public.perfiles`; no altera
-- ningún objeto de `public`.
--
-- DENEGACIÓN EXPLÍCITA, NUNCA «VACÍO» (plan de escalabilidad, F2 §5): un lead
-- fuera del ámbito, borrado o inexistente responde `42501`. Un historial
-- vacío sería indistinguible de un bug, y esta migración nace de uno.
--
-- LAS SEÑALES viajan en el mismo payload porque preguntan «alguna vez» sobre
-- TODO el historial, no sobre la página: `retrocesoPorAnularReunion` baja de
-- etapa si nunca hubo `reunion_realizada`, y una página de 100 filas podría
-- ocultar la que sí hubo. Van en jsonb para que la firma no cambie si mañana
-- hace falta otra (decisión #9 del plan: cambiar la firma de una RPC pública
-- es drop + defaults + revoke/grant).
--
-- VIGÍA DE CONTADORES CRUDOS (`private.assert_analitica_leads_citas`): ninguna
-- función de esta migración usa `count(` ni `sum(1)`. El «hay más» lo decide
-- el front pidiendo `limite + 1` (mismo contrato que la cartera keyset).
--
-- COORDINADOR: recibe 42501 en TODO lead, también en los de la cola que
-- reparte. No es un bug: por diseño C1 (`20260721120000`) su ámbito de leads
-- es ∅ y ninguna pantalla suya abre la ficha. La RPC vieja le devolvía `[]`;
-- esta le dice que no. La matriz `test-rls` lo clava como contrato.
--
-- FIRMAS: `nombre_de_autor` resuelve MENOS nombres que la RPC vieja (solo
-- `crm.equipo`; la vieja unía `public.perfiles` entero bajo DEFINER). Medido
-- en producción el 19/09/2026: 0 actividades con autor fuera del roster y 0
-- con autor nulo, así que hoy ninguna ficha cambia de firma.
--
-- `crm.actividades_del_ambito_fn` NO se toca: sigue viva para las pantallas
-- de equipo hasta que la Fase 3 del plan las pase al servidor
-- (CERRAR → OBSERVAR → DERRIBAR).
--
-- REVERSIÓN: `drop function crm.actividades_de_lead_fn(uuid,integer,timestamptz,uuid);`
-- `drop function private.actividades_de_lead_core(uuid,integer,timestamptz,uuid);`
-- `drop function private.nombre_de_autor(uuid);`
-- `drop function private.assert_actividades_de_lead();`
-- `drop function private.assert_actividades_de_lead_mutantes();`
-- `drop function private.assert_actividades_de_lead_base();`. El front vuelve
-- a filtrar la lista del ámbito (con su recorte). Nada de datos que deshacer:
-- esta migración solo lee.
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';

-- ── Base del trinquete: lo que TIENE que ser cierto antes y después ──────────
-- Comprobaciones compartidas por el preflight y por el gate propio, para que
-- las dos no puedan divergir: las policies de las que depende el diseño (por
-- huella Y por conjunto: una permisiva nueva no cambia el md5 de la vieja pero
-- sí rompe la co-extensividad), los grants que la cadena INVOKER necesita y el
-- USAGE sobre `private`. Sin `count(`: la vigía de contadores crudos marcaría
-- una función que mencione `crm.leads` y cuente.
create function private.assert_actividades_de_lead_base() returns text
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
  if not has_column_privilege('authenticated', 'crm.leads', 'id', 'SELECT') then
    raise exception 'authenticated no puede leer crm.leads.id: la denegacion explicita no funcionaria';
  end if;
  if not has_table_privilege('authenticated', 'crm.actividades', 'SELECT') then
    raise exception 'authenticated no puede leer crm.actividades: el nucleo no devolveria nada';
  end if;

  -- Las dos policies co-extensivas, tal cual se auditaron el 19/09/2026.
  select md5(pg_get_expr(pol.polqual, pol.polrelid)) into v_huella
  from pg_policy pol
  where pol.polrelid = 'crm.actividades'::regclass and pol.polname = 'actividades_select';
  if v_huella is distinct from 'e80e3af900b8d9616c28dcd836f1ac94' then
    raise exception 'actividades_select cambio desde la auditoria (md5 %): re-auditar',
      coalesce(v_huella, 'ausente');
  end if;
  select md5(pg_get_expr(pol.polqual, pol.polrelid)) into v_huella
  from pg_policy pol
  where pol.polrelid = 'crm.leads'::regclass and pol.polname = 'leads_select';
  if v_huella is distinct from '073deaeb5700bac14209ec795b71567e' then
    raise exception 'leads_select cambio desde la auditoria (md5 %): re-auditar',
      coalesce(v_huella, 'ausente');
  end if;

  -- El CONJUNTO de permisivas de lectura: exactamente una por tabla, solo para
  -- authenticated, y la restrictiva del actor activo presente en ambas.
  select array_agg(pol.polname::text order by pol.polname) into v_nombres
  from pg_policy pol
  where pol.polrelid = 'crm.leads'::regclass and pol.polpermissive and pol.polcmd in ('r', '*');
  if v_nombres is distinct from array['leads_select']::text[] then
    raise exception 'crm.leads tiene otras permisivas de lectura (%): la co-extensividad ya no esta garantizada',
      coalesce(array_to_string(v_nombres, ','), 'ninguna');
  end if;
  select array_agg(pol.polname::text order by pol.polname) into v_nombres
  from pg_policy pol
  where pol.polrelid = 'crm.actividades'::regclass and pol.polpermissive and pol.polcmd in ('r', '*');
  if v_nombres is distinct from array['actividades_select']::text[] then
    raise exception 'crm.actividades tiene otras permisivas de lectura (%): la co-extensividad ya no esta garantizada',
      coalesce(array_to_string(v_nombres, ','), 'ninguna');
  end if;
  if exists (
    select 1 from pg_policy pol
    where pol.polrelid in ('crm.leads'::regclass, 'crm.actividades'::regclass)
      and pol.polname in ('leads_select', 'actividades_select')
      and pol.polroles is distinct from array['authenticated'::regrole::oid]
  ) then
    raise exception 'leads_select/actividades_select ya no aplican solo a authenticated';
  end if;
  if not exists (
    select 1 from pg_policy pol
    where pol.polrelid = 'crm.leads'::regclass and pol.polname = 'crm_actor_activo_gate' and not pol.polpermissive
  ) or not exists (
    select 1 from pg_policy pol
    where pol.polrelid = 'crm.actividades'::regclass and pol.polname = 'crm_actor_activo_gate' and not pol.polpermissive
  ) then
    raise exception 'Falta la restrictiva crm_actor_activo_gate en crm.leads o crm.actividades';
  end if;
  return 'OK: policies selladas por huella y por conjunto, grants de la cadena invoker presentes';
end;
$function$;
comment on function private.assert_actividades_de_lead_base() is
  'Base del trinquete del historial por lead: ayudantes de autoridad, USAGE/grants de la cadena invoker, y las policies leads_select/actividades_select selladas por md5 y por conjunto (con la restrictiva crm_actor_activo_gate).';
revoke all on function private.assert_actividades_de_lead_base()
  from public, anon, authenticated, service_role;

do $preflight$
begin
  perform private.assert_actividades_de_lead_base();
  if to_regprocedure('crm.actividades_de_lead_fn(uuid,integer,timestamptz,uuid)') is not null
     or to_regprocedure('private.actividades_de_lead_core(uuid,integer,timestamptz,uuid)') is not null
     or to_regprocedure('private.nombre_de_autor(uuid)') is not null then
    raise exception 'El historial por lead ya esta instalado';
  end if;
end;
$preflight$;

-- ── AYUDANTE · el único salto privilegiado ───────────────────────────────────
-- Nombre de quien firmó una gestión. Solo miembros del CRM (`crm.equipo`,
-- históricos incluidos): un uuid que no sea de un colega devuelve NULL, así
-- que no sirve para resolver nombres de clientes ni de nadie más. Y solo para
-- un actor ADMITIDO al CRM (gate interno, convención de los helpers de
-- `private` desde los cimientos): aunque `private` no está expuesto a la API,
-- si algún día lo estuviera por error, esto no serviría de oráculo de nombres.
create function private.nombre_de_autor(p_id uuid) returns text
language sql
stable
security definer
set search_path to ''
as $function$
  select p.nombre_completo
  from public.perfiles p
  where p.id = p_id
    and (select private.puede_acceder_crm())
    and exists (select 1 from crm.equipo e where e.perfil_id = p.id);
$function$;

comment on function private.nombre_de_autor(uuid) is
  'AYUDANTE: nombre de un miembro del CRM (histórico incluido) para firmar gestiones. DEFINER acotado a crm.equipo y a actores admitidos al CRM; para cualquier otro uuid o actor devuelve NULL.';

revoke all on function private.nombre_de_autor(uuid)
  from public, anon, authenticated, service_role;
grant execute on function private.nombre_de_autor(uuid) to authenticated;

-- ── CAPA 2 · NÚCLEO ─────────────────────────────────────────────────────────
-- Una página keyset `(creado_en desc, id asc)` del historial de un lead y sus
-- señales «alguna vez». `security invoker`: se ejecuta bajo la RLS del actor
-- (`actividades_select`); no interpreta autenticación ni autoridad. Los
-- empates de `creado_en` son frecuentes —`now()` es el de la transacción, y
-- el trigger de avance de etapa escribe su fila en la misma— así que el
-- desempate por `id` es parte del cursor, no un adorno. Los sentidos son
-- MIXTOS (desc, asc): la comparación no puede escribirse como tupla.
create function private.actividades_de_lead_core(
  p_lead uuid,
  p_limite integer,
  p_antes_de timestamptz,
  p_antes_id uuid
) returns jsonb
language sql
stable
security invoker
set search_path to ''
as $function$
  with pagina as (
    select a.id, a.lead_id, a.tipo, a.detalle, a.creado_por, a.creado_en
    from crm.actividades a
    where a.lead_id = p_lead
      and (
        p_antes_de is null
        or a.creado_en < p_antes_de
        or (a.creado_en = p_antes_de and a.id > p_antes_id)
      )
    order by a.creado_en desc, a.id asc
    limit p_limite
  )
  select jsonb_build_object(
    'version', 1,
    'items', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', pg.id,
          'lead_id', pg.lead_id,
          'tipo', pg.tipo,
          'detalle', pg.detalle,
          'autor_nombre', coalesce(private.nombre_de_autor(pg.creado_por), '—'),
          'creado_en', pg.creado_en
        )
        order by pg.creado_en desc, pg.id asc
      )
      from pagina pg
    ), '[]'::jsonb),
    -- Una sola pasada por el historial del lead para las tres señales
    -- (auditoría RLS del 19/09): bool_or/max filter, nunca count(.
    'senales', (
      select jsonb_build_object(
        'tiene_reunion_realizada', coalesce(bool_or(a.tipo = 'reunion_realizada'), false),
        'tiene_contacto', coalesce(bool_or(a.tipo in (
          'llamada_realizada', 'llamada_no_contestada',
          'whatsapp_enviado', 'whatsapp_recibido', 'reunion_realizada')), false),
        'ultima_conversacion_en', max(a.creado_en) filter (where a.tipo in (
          'llamada_realizada', 'whatsapp_recibido', 'reunion_realizada'))
      )
      from crm.actividades a
      where a.lead_id = p_lead
    )
  );
$function$;

comment on function private.actividades_de_lead_core(uuid, integer, timestamptz, uuid) is
  'NÚCLEO: página keyset (creado_en desc, id asc) del historial de UN lead bajo la RLS del actor, más las señales «alguna vez» (reunión realizada, contacto, última conversación). Puro: sin auth ni autoridad propia.';

revoke all on function private.actividades_de_lead_core(uuid, integer, timestamptz, uuid)
  from public, anon, authenticated, service_role;
-- Lo llama una puerta INVOKER, así que corre como el actor: necesita EXECUTE.
-- `private` no está expuesto a la API: PostgREST no puede invocarlo directo.
grant execute on function private.actividades_de_lead_core(uuid, integer, timestamptz, uuid)
  to authenticated;

-- ── CAPA 3 · PUERTA ─────────────────────────────────────────────────────────
create function crm.actividades_de_lead_fn(
  p_lead_id uuid,
  p_limite integer default 100,
  p_antes_de timestamptz default null,
  p_antes_id uuid default null
) returns jsonb
language plpgsql
stable
security invoker
set search_path to ''
as $function$
begin
  -- EL INPUT SE VALIDA ANTES DE LEER NADA.
  if p_lead_id is null then
    raise exception 'Parametro p_lead_id obligatorio' using errcode = '22023';
  end if;
  if p_limite is null or p_limite < 1 or p_limite > 500 then
    raise exception 'Parametro p_limite invalido' using errcode = '22023';
  end if;
  -- Cursor A MEDIAS = páginas que se saltan filas en silencio. O los dos
  -- componentes o ninguno: el desempate por id es parte del cursor.
  if (p_antes_de is null) <> (p_antes_id is null) then
    raise exception 'Cursor incompleto: p_antes_de y p_antes_id viajan juntos'
      using errcode = '22023';
  end if;

  -- Guardia de ADMISIÓN (P04: revocado ≠ ajeno al CRM). El ALCANCE lo pone la
  -- RLS, ver cabecera.
  if not private.puede_acceder_crm() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  -- Denegación EXPLÍCITA: la propia policy `leads_select` decide si este actor
  -- ve este lead (fuera de ámbito, borrado o inexistente ⇒ misma respuesta).
  -- Nunca un historial vacío que se confunda con «sin gestiones».
  if not exists (select 1 from crm.leads l where l.id = p_lead_id) then
    raise exception 'Lead fuera de tu cartera' using errcode = '42501';
  end if;

  return private.actividades_de_lead_core(p_lead_id, p_limite, p_antes_de, p_antes_id);
end;
$function$;

comment on function crm.actividades_de_lead_fn(uuid, integer, timestamptz, uuid) is
  'PUERTA: historial de UN lead por cursor keyset (creado_en desc, id asc) con señales «alguna vez». SECURITY INVOKER: el alcance lo ponen actividades_select y leads_select; 42501 explícito si el lead no es visible. Sin ventana de fecha ni tope global.';

revoke all on function crm.actividades_de_lead_fn(uuid, integer, timestamptz, uuid)
  from public, anon, authenticated, service_role;
grant execute on function crm.actividades_de_lead_fn(uuid, integer, timestamptz, uuid)
  to authenticated;

-- ── Gate propio ──────────────────────────────────────────────────────────────
-- Trinquete: puerta y núcleo siguen siendo INVOKER (el alcance es de la RLS),
-- estables y con search_path vacío; el ayudante sigue siendo el ÚNICO definer;
-- las tres funciones exponen EXECUTE exactamente a `authenticated`; y las dos
-- policies de las que depende el diseño siguen siendo las auditadas.
create function private.assert_actividades_de_lead() returns text
language plpgsql stable security definer set search_path='' as $function$
declare
  v_puerta constant text := 'crm.actividades_de_lead_fn(uuid,integer,timestamptz,uuid)';
  v_nucleo constant text := 'private.actividades_de_lead_core(uuid,integer,timestamptz,uuid)';
  v_ayudante constant text := 'private.nombre_de_autor(uuid)';
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
      raise exception 'Contrato del historial por lead alterado (debe ser INVOKER, stable, search_path vacio): %', v_firma;
    end if;
  end loop;

  -- El único DEFINER: con su gate interno de admisión (strpos, no LIKE: el
  -- nombre lleva guiones bajos y en LIKE `_` es comodín).
  v_id := to_regprocedure(v_ayudante);
  if v_id is null or not exists(
    select 1 from pg_proc p
    where p.oid = v_id and p.prosecdef
      and p.proowner = 'postgres'::regrole::oid
      and p.provolatile = 's'
      and p.proconfig @> array['search_path=""']
      and strpos(p.prosrc, 'puede_acceder_crm') > 0
  ) then
    raise exception 'El ayudante del nombre de autor perdio su forma (DEFINER, stable, search_path vacio, gate interno): %', v_ayudante;
  end if;

  -- EXECUTE exactamente para `authenticated`: ni anon, ni service_role, ni PUBLIC.
  foreach v_firma in array array[v_puerta, v_nucleo, v_ayudante] loop
    v_id := to_regprocedure(v_firma);
    if not has_function_privilege('authenticated', v_id, 'EXECUTE')
       or exists(
         select 1 from pg_proc p
         cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
         where p.oid = v_id
           and a.grantee not in ('postgres'::regrole::oid, 'authenticated'::regrole::oid)
       ) then
      raise exception 'ACL del historial por lead alterado: %', v_firma;
    end if;
  end loop;

  -- El diseño descansa en que `actividades_select` y `leads_select` sigan
  -- siendo co-extensivas (por huella y por conjunto) y en los grants de la
  -- cadena invoker: la base del trinquete lo grita si alguien lo toca.
  perform private.assert_actividades_de_lead_base();

  return 'OK: historial por lead bajo la RLS, un solo salto privilegiado (nombre del autor, con gate interno) y policies selladas';
end;
$function$;
comment on function private.assert_actividades_de_lead() is
  'Trinquete del historial por lead: puerta y núcleo INVOKER con search_path vacío, ayudante DEFINER único con gate interno, EXECUTE solo para authenticated, y las policies actividades_select/leads_select selladas por md5 y por conjunto.';
revoke all on function private.assert_actividades_de_lead()
  from public, anon, authenticated, service_role;

-- ── Mutantes del trinquete (regla de la casa: por cada defensa, un mutante) ──
-- SOLO PARA EL BANCO (lo llama test-rls por la vía fuera de banda). Cada
-- mutante vive en su propia subtransacción: se aplica la mutación, se llama al
-- gate y —grite o no— la subtransacción se deshace. Si un mutante NO es
-- detectado, la función falla con su nombre. Nunca deja el esquema alterado.
create function private.assert_actividades_de_lead_mutantes() returns text
language plpgsql volatile security definer set search_path='' as $function$
declare
  v_detectados integer := 0;
begin
  -- Mutante 1: el ayudante pierde el DEFINER.
  begin
    alter function private.nombre_de_autor(uuid) security invoker;
    perform private.assert_actividades_de_lead();
    raise exception 'MUTANTE 1 NO DETECTADO: el ayudante invoker paso el gate';
  exception when others then
    if sqlerrm like 'MUTANTE % NO DETECTADO%' then raise; end if;
    v_detectados := v_detectados + 1;
  end;
  -- Mutante 2: la policy de actividades se abre (la huella cambia).
  begin
    alter policy actividades_select on crm.actividades using (true);
    perform private.assert_actividades_de_lead();
    raise exception 'MUTANTE 2 NO DETECTADO: actividades_select abierta paso el gate';
  exception when others then
    if sqlerrm like 'MUTANTE % NO DETECTADO%' then raise; end if;
    v_detectados := v_detectados + 1;
  end;
  -- Mutante 3: una permisiva NUEVA sobre crm.leads (la huella de la vieja no cambia).
  begin
    create policy leads_mutante_historial on crm.leads for select to authenticated using (true);
    perform private.assert_actividades_de_lead();
    raise exception 'MUTANTE 3 NO DETECTADO: una permisiva nueva en crm.leads paso el gate';
  exception when others then
    if sqlerrm like 'MUTANTE % NO DETECTADO%' then raise; end if;
    v_detectados := v_detectados + 1;
  end;
  -- Mutante 4: el ayudante conserva la forma pero pierde su gate interno.
  begin
    create or replace function private.nombre_de_autor(p_id uuid) returns text
      language sql stable security definer set search_path to ''
      as 'select p.nombre_completo from public.perfiles p where p.id = p_id';
    perform private.assert_actividades_de_lead();
    raise exception 'MUTANTE 4 NO DETECTADO: el ayudante sin gate interno paso el gate';
  exception when others then
    if sqlerrm like 'MUTANTE % NO DETECTADO%' then raise; end if;
    v_detectados := v_detectados + 1;
  end;
  -- Mutante 5: la puerta pasa a DEFINER (dejaria de apoyarse en la RLS).
  begin
    alter function crm.actividades_de_lead_fn(uuid, integer, timestamptz, uuid) security definer;
    perform private.assert_actividades_de_lead();
    raise exception 'MUTANTE 5 NO DETECTADO: la puerta definer paso el gate';
  exception when others then
    if sqlerrm like 'MUTANTE % NO DETECTADO%' then raise; end if;
    v_detectados := v_detectados + 1;
  end;
  return format('OK: %s mutantes detectados por private.assert_actividades_de_lead()', v_detectados);
end;
$function$;
comment on function private.assert_actividades_de_lead_mutantes() is
  'Mutantes del trinquete del historial por lead (solo banco): cada mutación vive en una subtransacción que se deshace; falla si el gate no la detecta.';
revoke all on function private.assert_actividades_de_lead_mutantes()
  from public, anon, authenticated, service_role;

do $postflight$
begin
  perform private.assert_actividades_de_lead();
  -- Los gates del mundo SLA, que también lee crm.actividades. Los otros
  -- cuatro controles del servidor (auditoría, analítica de leads/citas,
  -- vigencia de analistas y piezas F7) están en ROJO en producción desde antes
  -- de este cambio y por trabajos ajenos a él; llamarlos aquí abortaría una
  -- migración que no los empeora ni los arregla.
  perform private.assert_sla_nucleo();
  perform private.assert_sla_operacion();
  perform private.assert_sla_comandos();
  perform private.assert_sla_avisos();
end;
$postflight$;

notify pgrst, 'reload schema';
commit;
$mig_historial$;

  -- 1) PIN: lo que la migración hizo ES verdad — las tres funciones y el gate
  --    existen con la definición publicada (md5 medidos en el banco) y el gate
  --    propio responde OK en ESTA base.
  if to_regprocedure('crm.actividades_de_lead_fn(uuid,integer,timestamptz,uuid)') is null
     or to_regprocedure('private.actividades_de_lead_core(uuid,integer,timestamptz,uuid)') is null
     or to_regprocedure('private.nombre_de_autor(uuid)') is null
     or to_regprocedure('private.assert_actividades_de_lead()') is null
     or md5(pg_get_functiondef('crm.actividades_de_lead_fn(uuid,integer,timestamptz,uuid)'::regprocedure)) is distinct from 'edef0f8628938e56487f7f3ec27f2c9b'
     or md5(pg_get_functiondef('private.actividades_de_lead_core(uuid,integer,timestamptz,uuid)'::regprocedure)) is distinct from 'b00cc5815f41ea2a29906524114002a8'
     or md5(pg_get_functiondef('private.nombre_de_autor(uuid)'::regprocedure)) is distinct from 'c9eed135efa0c03a04360bfcf9bdf490' then
    raise exception 'registrar historial por lead: la migración 20260919185718 no está aplicada tal cual — aplicarla antes de registrar';
  end if;
  if private.assert_actividades_de_lead() not like 'OK:%' then
    raise exception 'registrar historial por lead: el gate propio no responde OK';
  end if;

  -- 2) La versión no puede existir con OTRO cuerpo.
  select count(*) into v_n from supabase_migrations.schema_migrations
   where version = '20260919185718' and statements is not null
     and (cardinality(statements) <> 1 or statements[1] <> v_cuerpo);
  if v_n > 0 then
    raise exception 'registrar historial por lead: la versión 20260919185718 existe con OTRO cuerpo — investigar antes de tocar';
  end if;

  -- 3) Registro (idempotente).
  insert into supabase_migrations.schema_migrations (version, name, statements)
  values ('20260919185718', 'crm_actividades_de_lead', array[v_cuerpo])
  on conflict (version) do nothing;

  -- 4) RELECTURA fail-closed: la fila EXACTA, o se cae la transacción entera.
  select count(*) into v_n from supabase_migrations.schema_migrations
   where version = '20260919185718' and name = 'crm_actividades_de_lead'
     and cardinality(statements) = 1 and statements[1] = v_cuerpo;
  if v_n <> 1 then
    raise exception 'registrar historial por lead: la relectura no encontró la fila exacta';
  end if;
end $reg_historial$;
