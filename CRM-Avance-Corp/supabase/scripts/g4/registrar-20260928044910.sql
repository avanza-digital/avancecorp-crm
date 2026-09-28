-- Registra 20260928044910 (crm_gestion_diaria_citas_lista) CON su cuerpo — fail-closed.
-- Orden de la casa: PRIMERO aplicar la migración con `db query --linked --file`, DESPUÉS este
-- registrador. El cuerpo embebido es el archivo de la migración tal cual (no editar a mano:
-- se regenera desde el archivo si la migración cambia antes de aplicarse).
do $reg_g4b$
declare v_n int; v_cuerpo text;
begin
  v_cuerpo := $mig_g4b$-- G4b (27/09/2026): la lista EXACTA de «Citas agendadas» de Gestión Diaria.
-- Plan G4 v2 aprobado por Miguel («G4a y luego G4b») y revisado por Codex
-- (P1: selector de ámbito explícito y roles explícitos; P2: rol nulo rechazado).
--
-- Una lectura nueva, sin escrituras ni tablas: puerta crm.gestion_diaria_citas_fn y
-- núcleo private.gestion_diaria_citas_core, ambos INVOKER bajo la RLS de crm.tareas.
--   · Definición IDÉNTICA a la cifra (private.gestion_diaria_llamadas y el pulso):
--     tareas `reunion` CREADAS en el día Lima [día, día+1), sin filtrar estado ni
--     activo en el SQL; la RLS efectiva es la misma que la de la cifra.
--   · Ámbito explícito (p_ambito) decidido y autorizado en el servidor:
--       'analista' (p_id = analista): Supervisión (su árbol) y Gerencia (toda la
--                 operación visible), el mismo roster canónico que pendientes.
--       'equipo'   (p_id = supervisor): sólo Gerencia; partición del PULSO
--                 (analistas activos cuyo supervisor activo más cercano es p_id).
--       'fuera'    (p_id nulo): sólo Gerencia; lo que el pulso agrupa en «fuera»:
--                 sin autor, autores fuera del roster y analistas sin supervisor.
--       'operacion'(p_id nulo): sólo Gerencia; todas.
--   · Roles explícitos ANTES del ámbito: Supervisión y Gerencia. Coordinación,
--     analistas, lector global y rol nulo: 42501, aunque los helpers los admitan.
--   · Orden y cursor por (creado_en, id); resumen.total antes de paginar.
-- Sin count(): el total sale de cardinality(array_agg()), como gestion_diaria_llamadas
-- (no es un contador nuevo: es la lista de la cifra que ya existe).
--
-- Gate: private.assert_gestion_diaria_citas() —huellas, INVOKER, search_path y ACL EXACTA
-- (aclexplode: solo postgres y authenticated) de la puerta y el núcleo, y huellas de las
-- fuentes de la cifra: gestion_diaria_llamadas, pulso_roster, equipo_ambito y las del pulso
-- (pulso_autores, pulso_dia, pulso_metricas, pulso_fn; auditor-rls)— enchufado a
-- private.assert_gestion_diaria() por identidad (huella del paraguas en la misma sentencia).
-- Registro: supabase/scripts/g4/registrar-20260928044910.sql, DESPUÉS de aplicar.
-- Reversa: supabase/scripts/g4/reversa-g4b.sql. Si el front ya abre la lista,
-- revertir PRIMERO el front y después la base.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';
do $preflight$
declare v_firma text; v_huella text;
begin
  perform private.assert_gestion_diaria();
  if to_regprocedure('private.gestion_diaria_citas_core(date,text,uuid,integer,timestamptz,uuid)') is not null
    or to_regprocedure('crm.gestion_diaria_citas_fn(date,text,uuid,integer,timestamptz,uuid)') is not null
    or to_regprocedure('private.assert_gestion_diaria_citas()') is not null then
    raise exception 'G4b: ya existe una pieza de G4b; revisar antes de continuar';
  end if;
  -- Huellas vivas exactas (producción, 27/09) de lo que se lee y de lo que se re-sella.
  for v_firma, v_huella in select * from (values
    ('private.assert_gestion_diaria()', '5d9dbf0850798fb5cb10942838740d54'),
    ('private.gestion_diaria_equipo_ambito(uuid)', 'af06caf4d0ea5d392d9c36f069b3501b'),
    ('private.gestion_diaria_pulso_roster()', 'f35b4f2402f1774ea3eba395c5b97f4f'),
    ('private.gestion_diaria_pulso_autorizar()', '14091efcebf71186c3fa76f12e4f266c'),
    ('private.gestion_diaria_llamadas(timestamptz,timestamptz,uuid[])', '7c5d14e65cc0e55e57214589d11e9c9d'),
    ('private.gestion_diaria_pulso_autores(timestamptz,timestamptz)', 'e73960545e7f637259db254c9e2a385b'),
    ('private.gestion_diaria_pulso_dia(date)', '0221659e73a2556099974324564f2164'),
    ('private.gestion_diaria_pulso_metricas(jsonb,integer)', 'cf96bd3c57c5302eadaa4ef3a29d92aa'),
    ('crm.gestion_diaria_pulso_fn(date)', 'ae43587d05ede1aa077f5924471c43ae'),
    ('crm.equipo_visible_fn()', '200162f4519586a6c68d8ccf0cf591f7')
  ) as h(firma, huella) loop
    if md5(pg_get_functiondef(to_regprocedure(v_firma))) is distinct from v_huella then
      raise exception 'G4b: cambió % en vivo; revisar antes de continuar', v_firma;
    end if;
  end loop;
end $preflight$;

create function private.gestion_diaria_citas_core(
  p_dia date, p_ambito text, p_id uuid, p_limite integer,
  p_despues_de timestamptz, p_despues_id uuid
) returns jsonb
language plpgsql stable security invoker set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text := private.rol_crm(v_uid);
  v_ahora timestamptz := statement_timestamp();
  v_hoy date := (v_ahora at time zone 'America/Lima')::date;
  v_ini timestamptz;
  v_fin timestamptz;
  v_ids uuid[] := '{}'::uuid[];
  v_con_equipo uuid[] := '{}'::uuid[];
  v_respuesta jsonb;
begin
  -- Roles explícitos ANTES de resolver el ámbito (Codex P1/P2): el rol nulo no pasa.
  if v_uid is null or not coalesce(v_rol in ('supervisor', 'gerencia'), false) then
    raise exception 'No autorizado para consultar citas' using errcode = '42501';
  end if;
  if p_dia is null or not isfinite(p_dia) or p_dia > v_hoy or v_hoy - p_dia > 365
    or p_ambito is null or p_ambito not in ('analista', 'equipo', 'fuera', 'operacion')
    or (p_ambito in ('analista', 'equipo')) <> (p_id is not null)
    or p_limite is null or p_limite < 1 or p_limite > 100
    or (p_despues_de is null) <> (p_despues_id is null)
    or (p_despues_de is not null and not isfinite(p_despues_de)) then
    raise exception 'Parámetros de citas inválidos' using errcode = '22023';
  end if;
  v_ini := p_dia::timestamp at time zone 'America/Lima';
  v_fin := (p_dia + 1)::timestamp at time zone 'America/Lima';

  if p_ambito = 'analista' then
    -- El roster canónico de pendientes: Supervisión su árbol; Gerencia toda la operación.
    -- Ajeno, inactivo e inexistente tienen idéntica respuesta.
    if not exists (select 1 from jsonb_array_elements(private.gestion_diaria_equipo_ambito(
        case when v_rol = 'supervisor' then v_uid end)->'roster') r
      where (r->>'analista_id')::uuid = p_id) then
      raise exception 'No autorizado para consultar citas' using errcode = '42501';
    end if;
    v_ids := array[p_id];
  elsif v_rol is distinct from 'gerencia' then
    raise exception 'No autorizado para consultar citas' using errcode = '42501';
  elsif p_ambito = 'equipo' then
    -- Partición del pulso: el supervisor activo más cercano de cada analista activo.
    if not exists (select 1 from crm.equipo_visible_fn() e
      where e.perfil_id = p_id and e.activo and e.rol_crm = 'supervisor') then
      raise exception 'No autorizado para consultar citas' using errcode = '42501';
    end if;
    select coalesce(array_agg(r.analista_id), '{}'::uuid[]) into v_ids
    from private.gestion_diaria_pulso_roster() r where r.supervisor_id = p_id;
  elsif p_ambito = 'fuera' then
    -- «fuera» es el complemento de los equipos: todo autor que no sea un analista con supervisor.
    select coalesce(array_agg(r.analista_id), '{}'::uuid[]) into v_con_equipo
    from private.gestion_diaria_pulso_roster() r where r.supervisor_id is not null;
  end if;

  -- Resumen y página comparten sentencia y RLS.
  with base as materialized (
    select t.id, t.vendedor_id, t.lead_id, t.vence_en, t.estado, t.creado_en
    from crm.tareas t
    where t.tipo = 'reunion' and t.creado_en >= v_ini and t.creado_en < v_fin
      and case p_ambito
        when 'operacion' then true
        when 'fuera' then t.vendedor_id is null or not (t.vendedor_id = any(v_con_equipo))
        else t.vendedor_id = any(v_ids)
      end
  ), resumen as (
    select coalesce(cardinality(array_agg(b.id)), 0) as total from base b
  ), sonda as materialized (
    select b.* from base b
    where p_despues_de is null or (b.creado_en, b.id) > (p_despues_de, p_despues_id)
    order by b.creado_en, b.id limit p_limite + 1
  ), pagina as materialized (
    select s.* from sonda s order by s.creado_en, s.id limit p_limite
  ), estado as (
    select coalesce(cardinality(array_agg(s.id)), 0) > p_limite as hay_mas from sonda s
  ), visibles as materialized (
    select e.perfil_id, e.nombre_completo from crm.equipo_visible_fn() e
    where e.perfil_id in (select p.vendedor_id from pagina p)
  )
  select jsonb_build_object(
    'version', 1, 'zona', 'America/Lima', 'dia', p_dia, 'ambito', p_ambito, 'id', p_id,
    'generado_en', v_ahora, 'limite', p_limite,
    'resumen', jsonb_build_object('total', r.total),
    'items', coalesce((select jsonb_agg(jsonb_build_object(
      'id', p.id, 'vendedor_id', p.vendedor_id,
      'vendedor_nombre', nullif(btrim(v.nombre_completo), ''),
      'lead_id', case when nullif(btrim(l.nombre_completo), '') is not null then l.id end,
      'lead_nombre', nullif(btrim(l.nombre_completo), ''),
      'vence_en', p.vence_en, 'estado', p.estado, 'creado_en', p.creado_en
    ) order by p.creado_en, p.id)
      from pagina p
      left join crm.leads l on l.id = p.lead_id
      left join visibles v on v.perfil_id = p.vendedor_id), '[]'::jsonb),
    'hay_mas', e.hay_mas,
    'siguiente_cursor', case when e.hay_mas then (select jsonb_build_object(
      'despues_de', p.creado_en, 'despues_id', p.id)
      from pagina p order by p.creado_en desc, p.id desc limit 1) end
  ) into v_respuesta from resumen r cross join estado e;
  return v_respuesta;
end;
$function$;
revoke all on function private.gestion_diaria_citas_core(date,text,uuid,integer,timestamptz,uuid)
  from public, anon, authenticated, service_role;
grant execute on function private.gestion_diaria_citas_core(date,text,uuid,integer,timestamptz,uuid) to authenticated;
comment on function private.gestion_diaria_citas_core(date,text,uuid,integer,timestamptz,uuid) is
  'G4b: citas agendadas (tareas reunion creadas en el día Lima) de un ámbito explícito: analista (Supervisión su árbol, Gerencia toda la operación), equipo/fuera/operacion (solo Gerencia, partición del pulso). INVOKER bajo RLS; cursor creado_en/id; misma definición que la cifra.';

create function crm.gestion_diaria_citas_fn(
  p_dia date, p_ambito text, p_id uuid default null, p_limite integer default 25,
  p_despues_de timestamptz default null, p_despues_id uuid default null
) returns jsonb
language sql stable security invoker set search_path = ''
as $function$
  select private.gestion_diaria_citas_core(p_dia, p_ambito, p_id, p_limite, p_despues_de, p_despues_id);
$function$;
revoke all on function crm.gestion_diaria_citas_fn(date,text,uuid,integer,timestamptz,uuid)
  from public, anon, authenticated, service_role;
grant execute on function crm.gestion_diaria_citas_fn(date,text,uuid,integer,timestamptz,uuid) to authenticated;
comment on function crm.gestion_diaria_citas_fn(date,text,uuid,integer,timestamptz,uuid) is
  'G4b: lista exacta de «Citas agendadas» de Gestión Diaria (tareas reunion creadas en el día Lima). Ámbitos: analista, equipo, fuera, operacion; límite 1–100, cursor creado_en/id, resumen.total antes de paginar. Sin escrituras.';

create function private.assert_gestion_diaria_citas() returns text
language plpgsql stable security definer set search_path = ''
as $function$
declare v_firma text; v_huella text;
begin
  for v_firma, v_huella in select * from (values
    ('private.gestion_diaria_citas_core(date,text,uuid,integer,timestamptz,uuid)', '904d3b0a853a6cf794943217fc957f03'),
    ('crm.gestion_diaria_citas_fn(date,text,uuid,integer,timestamptz,uuid)', 'fd2b0376be5e8c6728e4c33776e1a9e4')
  ) as firmas(firma, huella) loop
    if not exists (select 1 from pg_proc p where p.oid = to_regprocedure(v_firma)
      and not p.prosecdef and p.provolatile = 's' and p.proowner = 'postgres'::regrole
      and p.proconfig = array['search_path=""']
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and not has_function_privilege('anon', p.oid, 'EXECUTE')
      and not has_function_privilege('service_role', p.oid, 'EXECUTE')
      and md5(pg_get_functiondef(p.oid)) = v_huella) then
      raise exception 'G4b: contrato, cuerpo o permisos alterados en %', v_firma;
    end if;
    -- ACL EXACTA (como F3/F5): EXECUTE solo para postgres y authenticated; PUBLIC es grantee 0.
    if exists (select 1 from pg_proc p
      cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
      where p.oid = to_regprocedure(v_firma)
        and a.grantee not in ('postgres'::regrole::oid, 'authenticated'::regrole::oid)) then
      raise exception 'G4b: EXECUTE fuera de postgres y authenticated en %', v_firma;
    end if;
  end loop;
  -- La lista ES la cifra: si cambia la definición de citas agendadas, la partición del
  -- pulso, el roster canónico o las fuentes del pulso que dan la cifra de equipo, «fuera»
  -- y operación, la lista se revisa junto con ellas (auditor-rls P2-1).
  for v_firma, v_huella in select * from (values
    ('private.gestion_diaria_llamadas(timestamp with time zone,timestamp with time zone,uuid[])', '7c5d14e65cc0e55e57214589d11e9c9d'),
    ('private.gestion_diaria_pulso_roster()', 'f35b4f2402f1774ea3eba395c5b97f4f'),
    ('private.gestion_diaria_equipo_ambito(uuid)', 'af06caf4d0ea5d392d9c36f069b3501b'),
    ('private.gestion_diaria_pulso_autores(timestamp with time zone,timestamp with time zone)', 'e73960545e7f637259db254c9e2a385b'),
    ('private.gestion_diaria_pulso_dia(date)', '0221659e73a2556099974324564f2164'),
    ('private.gestion_diaria_pulso_metricas(jsonb,integer)', 'cf96bd3c57c5302eadaa4ef3a29d92aa'),
    ('crm.gestion_diaria_pulso_fn(date)', 'ae43587d05ede1aa077f5924471c43ae')
  ) as fuentes(firma, huella) loop
    if md5(pg_get_functiondef(to_regprocedure(v_firma))) is distinct from v_huella then
      raise exception 'G4b: cambió % y la lista de citas debe revisarse con la cifra', v_firma;
    end if;
  end loop;
  return 'OK: citas G4b INVOKER con ACL exacta (postgres y authenticated), misma definición que la cifra y fuentes del pulso selladas';
end;
$function$;
revoke all on function private.assert_gestion_diaria_citas() from public, anon, authenticated, service_role;
comment on function private.assert_gestion_diaria_citas() is
  'Gate G4b: huellas, INVOKER, ACL exacta y search_path de la lista de citas, y huellas de las fuentes de su cifra (llamadas, roster, ámbito y pulso).';
-- El gate creado debe ser EXACTAMENTE el revisado.
do $gate$
begin
  if md5(pg_get_functiondef('private.assert_gestion_diaria_citas()'::regprocedure)) is distinct from '12012959d2e751c43df86b847dcce037' then
    raise exception 'G4b: el gate creado no es el revisado';
  end if;
end $gate$;

-- Enchufar el gate nuevo al paraguas, sustituyendo un fragmento que aparece una sola vez
-- (patrón de H3). El cuerpo resultante se comprueba contra su huella revisada.
do $enchufar$
declare
  v_def text := pg_get_functiondef('private.assert_gestion_diaria()'::regprocedure);
  v_viejo text := $v$private.assert_gestion_diaria_pendientes() || ']'$v$;
  v_nuevo text := $v$private.assert_gestion_diaria_pendientes()
    || '] [' || private.assert_gestion_diaria_citas() || ']'$v$;
begin
  -- Por identidad en esta misma sentencia: nada de copiar un cambio ajeno confirmado entre el
  -- preflight y aquí (READ COMMITTED ve lo confirmado antes de cada sentencia).
  if md5(v_def) is distinct from '5d9dbf0850798fb5cb10942838740d54' then
    raise exception 'G4b: el paraguas cambió antes de enchufar el gate de citas';
  end if;
  if (length(v_def) - length(replace(v_def, v_viejo, ''))) <> length(v_viejo) then
    raise exception 'G4b: el cierre del paraguas no aparece una sola vez en assert_gestion_diaria()';
  end if;
  execute replace(v_def, v_viejo, v_nuevo);
  if md5(pg_get_functiondef('private.assert_gestion_diaria()'::regprocedure)) is distinct from '58208b4fba6d2f76554e19e21444fe94' then
    raise exception 'G4b: el paraguas re-sellado no es el revisado';
  end if;
end $enchufar$;

do $postflight$
begin
  if private.assert_gestion_diaria() not like '%OK: citas G4b%' then
    raise exception 'G4b: el paraguas no ejecuta el gate de citas';
  end if;
  perform private.assert_sla_nucleo();
  perform private.assert_sla_operacion();
  perform private.assert_sla_comandos();
  perform private.assert_sla_avisos();
end $postflight$;
notify pgrst, 'reload schema';
commit;
$mig_g4b$;

  -- 1) La migración tiene que estar aplicada TAL CUAL: las tres piezas y el paraguas con
  --    las huellas revisadas, y el gate respondiendo OK. to_regprocedure(): una pieza que
  --    falta da NULL (y este mensaje), no otro error.
  if md5(pg_get_functiondef(to_regprocedure('private.gestion_diaria_citas_core(date,text,uuid,integer,timestamptz,uuid)'))) is distinct from '904d3b0a853a6cf794943217fc957f03'
     or md5(pg_get_functiondef(to_regprocedure('crm.gestion_diaria_citas_fn(date,text,uuid,integer,timestamptz,uuid)'))) is distinct from 'fd2b0376be5e8c6728e4c33776e1a9e4'
     or md5(pg_get_functiondef(to_regprocedure('private.assert_gestion_diaria_citas()'))) is distinct from '12012959d2e751c43df86b847dcce037'
     or md5(pg_get_functiondef(to_regprocedure('private.assert_gestion_diaria()'))) is distinct from '58208b4fba6d2f76554e19e21444fe94' then
    raise exception 'registrar G4b: la migración 20260928044910 no está aplicada tal cual — aplicarla antes de registrar';
  end if;
  if private.assert_gestion_diaria_citas() not like 'OK:%' then
    raise exception 'registrar G4b: el gate propio no responde OK';
  end if;

  -- 2) La versión no puede existir con OTRO cuerpo.
  select count(*) into v_n from supabase_migrations.schema_migrations
   where version = '20260928044910' and statements is not null
     and (cardinality(statements) <> 1 or statements[1] <> v_cuerpo);
  if v_n > 0 then
    raise exception 'registrar G4b: la versión 20260928044910 existe con OTRO cuerpo — investigar antes de tocar';
  end if;

  -- 3) Registro (idempotente).
  insert into supabase_migrations.schema_migrations (version, name, statements)
  values ('20260928044910', 'crm_gestion_diaria_citas_lista', array[v_cuerpo])
  on conflict (version) do nothing;

  -- 4) RELECTURA fail-closed: la fila EXACTA, o se cae la transacción entera.
  select count(*) into v_n from supabase_migrations.schema_migrations
   where version = '20260928044910' and name = 'crm_gestion_diaria_citas_lista'
     and cardinality(statements) = 1 and statements[1] = v_cuerpo;
  if v_n <> 1 then
    raise exception 'registrar G4b: la relectura no encontró la fila exacta';
  end if;
end $reg_g4b$;
