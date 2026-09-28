ROLE: SECONDARY_REVIEWER.
Claude is the PRIMARY agent.

Do not modify files. Do not implement the task. Do not invoke Claude.
Do not delegate to another coding agent. Do not create another review chain.
Follow .ai/REVIEW_PROTOCOL.md (its content is transcribed at the end).

Responde en español. No tienes shell, red ni base de datos: todo lo que debes juzgar está
transcrito aquí. Formato obligatorio: VERDICT (PASS / CHANGES_REQUESTED / BLOCK), SUMMARY,
FINDINGS P0–P3 con evidencia (archivo:línea o fragmento citado de este encargo), TEST GAPS,
REGRESSION RISKS, RECOMMENDED NEXT ACTIONS, CONFIDENCE. Sin hallazgo sin evidencia; marca como
hipótesis lo no demostrado. Omite secciones vacías.

# Encargo: REFUTAR el CÓDIGO de G4b (lista exacta de «Citas agendadas») antes de producción — LEVEL 3

Ya revisaste el PLAN G4 (tus P1 para G4b: selector de ámbito explícito que distinga «fuera», y roles
supervisor/gerencia comprobados en el núcleo antes del ámbito). Esta es la revisión del CÓDIGO de G4b. G4a
(pendientes para gerencia) ya está APLICADA en producción el 28/09 (núcleo a0bde87d…, gate pendientes 6aecb25a…).

Refuta: fugas (leads, analistas fuera de ámbito), lista ≠ cifra en algún ámbito (analista / equipo / fuera /
operación), autorización (rol nulo, lector global, coordinación, analista, anon, supervisor con ámbitos ajenos),
re-sellado del paraguas `assert_gestion_diaria()`, reversa, pruebas que no acreditan lo que dicen, contrato del
front (strict, coherencia, estados de tarea) y orden de publicación.

## Verificación comunicada por el agente que lo implementó (sin revisar por mí todavía)
- `npm run check` PASS (4719 pruebas).
- Banco Docker aislado (esquema de prod por dump, paridad 27/27): migración aplicada, reversa exacta y reaplicada,
  antes y después de G4a; `test-g4b.sql` → G4B_OK; 2 mutantes (borde del día `<=` y «fuera» sin las sin autor)
  cazados por «lista = cifra»; `test-g4a.sql` sigue G4A_OK con G4b instalada.
- Hallazgo del agente: el CHECK vivo de `crm.tareas.estado` admite `reprogramada`; añadido al esquema del front.
- Riesgo declarado: el total usa `cardinality(array_agg())` (como `gestion_diaria_llamadas`), fuera del censo analítico.
- Postventa: con `multiempresa_flags` vacía en el banco no se ejercitó su visibilidad específica (hipótesis:
  lista y cifra comparten RLS).

## Migración `supabase/migrations/20260928044910_crm_gestion_diaria_citas_lista.sql`
```sql
-- G4b (27/09/2026): la lista EXACTA de «Citas agendadas» de Gestión Diaria.
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
-- Gate: private.assert_gestion_diaria_citas() (huellas, INVOKER, ACL, search_path y
-- las fuentes de la cifra) enchufado a private.assert_gestion_diaria().
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
  end loop;
  -- La lista ES la cifra: si cambia la definición de citas agendadas, la partición del
  -- pulso o el roster canónico, la lista se revisa junto con ellas.
  for v_firma, v_huella in select * from (values
    ('private.gestion_diaria_llamadas(timestamp with time zone,timestamp with time zone,uuid[])', '7c5d14e65cc0e55e57214589d11e9c9d'),
    ('private.gestion_diaria_pulso_roster()', 'f35b4f2402f1774ea3eba395c5b97f4f'),
    ('private.gestion_diaria_equipo_ambito(uuid)', 'af06caf4d0ea5d392d9c36f069b3501b')
  ) as fuentes(firma, huella) loop
    if md5(pg_get_functiondef(to_regprocedure(v_firma))) is distinct from v_huella then
      raise exception 'G4b: cambió % y la lista de citas debe revisarse con la cifra', v_firma;
    end if;
  end loop;
  return 'OK: citas G4b INVOKER con ACL exacta, misma definición que la cifra y partición del pulso';
end;
$function$;
revoke all on function private.assert_gestion_diaria_citas() from public, anon, authenticated, service_role;
comment on function private.assert_gestion_diaria_citas() is
  'Gate G4b: huellas, INVOKER, ACL y search_path de la lista de citas y de las fuentes de su cifra.';

-- Enchufar el gate nuevo al paraguas, sustituyendo un fragmento que aparece una sola vez
-- (patrón de H3). El cuerpo resultante se comprueba contra su huella revisada.
do $enchufar$
declare
  v_def text := pg_get_functiondef('private.assert_gestion_diaria()'::regprocedure);
  v_viejo text := $v$private.assert_gestion_diaria_pendientes() || ']'$v$;
  v_nuevo text := $v$private.assert_gestion_diaria_pendientes()
    || '] [' || private.assert_gestion_diaria_citas() || ']'$v$;
begin
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
```

## Reversa `supabase/scripts/g4/reversa-g4b.sql`
```sql
-- Reversa de G4b (20260928044910): desenchufa el gate de citas del paraguas y retira
-- las tres piezas nuevas (sólo lectura: no hay datos que restaurar). Si el front ya
-- abre la lista de citas, revertir PRIMERO el front (release anterior) y después esto.
-- Aplicar en un solo mensaje (supabase db query --linked --file …), como la migración.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';
do $preflight$
begin
  if md5(pg_get_functiondef('private.assert_gestion_diaria()'::regprocedure)) is distinct from '58208b4fba6d2f76554e19e21444fe94' then
    raise exception 'Reversa G4b: el paraguas vivo no es el de G4b; no se toca';
  end if;
end $preflight$;
do $desenchufar$
declare
  v_def text := pg_get_functiondef('private.assert_gestion_diaria()'::regprocedure);
  v_nuevo text := $v$private.assert_gestion_diaria_pendientes()
    || '] [' || private.assert_gestion_diaria_citas() || ']'$v$;
  v_viejo text := $v$private.assert_gestion_diaria_pendientes() || ']'$v$;
begin
  if (length(v_def) - length(replace(v_def, v_nuevo, ''))) <> length(v_nuevo) then
    raise exception 'Reversa G4b: el enchufe del gate de citas no aparece una sola vez';
  end if;
  execute replace(v_def, v_nuevo, v_viejo);
  if md5(pg_get_functiondef('private.assert_gestion_diaria()'::regprocedure)) is distinct from '5d9dbf0850798fb5cb10942838740d54' then
    raise exception 'Reversa G4b: el paraguas no quedó como antes';
  end if;
end $desenchufar$;
drop function private.assert_gestion_diaria_citas();
drop function crm.gestion_diaria_citas_fn(date,text,uuid,integer,timestamptz,uuid);
drop function private.gestion_diaria_citas_core(date,text,uuid,integer,timestamptz,uuid);
do $postflight$
begin
  perform private.assert_gestion_diaria();
end $postflight$;
notify pgrst, 'reload schema';
commit;
```

## Pruebas `supabase/scripts/g4/test-g4b.sql`
```sql
-- G4b: lista exacta de «Citas agendadas». Datos sintéticos; lecturas como
-- authenticated/anon con identidad efectiva; todo termina en ROLLBACK.
-- Requiere la migración 20260928044910 instalada en el banco sintético G4.
-- La lista ES la cifra: se compara con el pulso, con el detalle por analista y con
-- private.gestion_diaria_llamadas, y los ámbitos de Gerencia deben PARTIR la operación.
begin;
set local statement_timeout = '120s';
set local timezone = 'America/Lima';
do $$ begin
  if shobj_description((select oid from pg_database where datname = current_database()), 'pg_database')
    is distinct from 'BANCO SINTETICO G4 / sin produccion' then
    raise exception 'G4b: sólo en el banco sintético G4';
  end if;
end $$;

create temporary table g4b_actores as
with v as (
  select e.perfil_id, e.supervisor_id, e.activo from crm.equipo e
  where private.rol_crm(e.perfil_id) = 'vendedor'
), con_sup as (select * from v where activo and exists (select 1 from crm.equipo s
    where s.perfil_id = v.supervisor_id and s.activo and private.rol_crm(s.perfil_id) = 'supervisor') order by perfil_id)
select (select perfil_id from con_sup limit 1) v1,
  (select supervisor_id from con_sup limit 1) sup1,
  (select perfil_id from con_sup where supervisor_id <> (select supervisor_id from con_sup limit 1) limit 1) ajeno,
  (select supervisor_id from con_sup where supervisor_id <> (select supervisor_id from con_sup limit 1) limit 1) sup2,
  -- «fuera»: analista activo sin supervisor ACTIVO por encima (sin jefe o con un jefe retirado).
  (select perfil_id from v where activo and (supervisor_id is null or not exists (select 1 from crm.equipo s
    where s.perfil_id = v.supervisor_id and s.activo and private.rol_crm(s.perfil_id) = 'supervisor')) order by perfil_id limit 1) fuera,
  -- Inactivo: fila del organigrama dada de baja (su rol efectivo ya es nulo).
  (select e.perfil_id from crm.equipo e join public.perfiles p on p.id = e.perfil_id where not e.activo and e.supervisor_id is not null order by 1 limit 1) inactivo,
  (select perfil_id from crm.equipo where private.rol_crm(perfil_id) = 'coordinador' and activo limit 1) coordinador,
  (select perfil_id from crm.equipo where private.rol_crm(perfil_id) = 'gerencia' and activo limit 1) gerente,
  (select id from public.perfiles where activo and rol = 'directorio' limit 1) global,
  gen_random_uuid() nadie,
  gen_random_uuid() inversionista,
  (now() at time zone 'America/Lima')::date - 1 as dia;
alter table g4b_actores add column ini timestamptz, add column fin timestamptz;
update g4b_actores set ini = dia::timestamp at time zone 'America/Lima', fin = (dia + 1)::timestamp at time zone 'America/Lima';
grant select on g4b_actores to authenticated, anon;

create function pg_temp.afirmar(ok boolean, mensaje text) returns void language plpgsql as $$
begin if ok is not true then raise exception 'G4b: %', mensaje; end if; end $$;
create function pg_temp.denegada(comando text, codigo text default '42501') returns void language plpgsql as $$
declare recibido text; begin
  begin execute comando; exception when others then recibido := sqlstate; end;
  perform pg_temp.afirmar(recibido = codigo, format('error esperado %s; recibido %s: %s', codigo, coalesce(recibido, 'ninguno'), comando));
end $$;
create function pg_temp.como(actor uuid) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', actor::text, true); end $$;
-- Todas las páginas de un ámbito, en orden (límite pequeño a propósito: ejercita el cursor).
create function pg_temp.lista(p_dia date, p_ambito text, p_id uuid, p_limite integer default 2) returns jsonb
language plpgsql as $$
declare v_pagina jsonb; v_items jsonb := '[]'::jsonb; v_de timestamptz; v_id uuid; v_total integer;
begin
  loop
    v_pagina := crm.gestion_diaria_citas_fn(p_dia, p_ambito, p_id, p_limite, v_de, v_id);
    perform pg_temp.afirmar(jsonb_array_length(v_pagina->'items') <= p_limite, 'página mayor que el límite');
    perform pg_temp.afirmar((v_pagina->>'hay_mas')::boolean = (v_pagina->'siguiente_cursor' <> 'null'::jsonb), 'hay_mas ⇔ cursor');
    if v_total is null then v_total := (v_pagina#>>'{resumen,total}')::integer;
    else perform pg_temp.afirmar(v_total = (v_pagina#>>'{resumen,total}')::integer, 'el total cambia entre páginas'); end if;
    v_items := v_items || (v_pagina->'items');
    exit when not (v_pagina->>'hay_mas')::boolean;
    v_de := (v_pagina#>>'{siguiente_cursor,despues_de}')::timestamptz;
    v_id := (v_pagina#>>'{siguiente_cursor,despues_id}')::uuid;
  end loop;
  perform pg_temp.afirmar(jsonb_array_length(v_items) = v_total, format('%s/%s: total %s y %s filas', p_ambito, p_id, v_total, jsonb_array_length(v_items)));
  -- Orden estricto (creado_en, id) sin repetidos.
  perform pg_temp.afirmar(not exists (select 1 from jsonb_array_elements(v_items) with ordinality a(x, n)
    join jsonb_array_elements(v_items) with ordinality b(y, m) on m = n + 1
    where ((a.x->>'creado_en')::timestamptz, (a.x->>'id')::uuid) >= ((b.y->>'creado_en')::timestamptz, (b.y->>'id')::uuid)),
    'orden (creado_en, id) estricto');
  return v_items;
end $$;
create function pg_temp.ids(p_items jsonb) returns uuid[] language sql immutable as $$
  select coalesce(array_agg((x->>'id')::uuid order by (x->>'id')::uuid), '{}') from jsonb_array_elements(p_items) x
$$;
-- Las fotos por rol se guardan en tablas creadas aquí (como postgres) y llenadas como authenticated.
create temporary table g4b_detalle(analista uuid, citas integer);
create temporary table g4b_pulso(p jsonb);
create temporary table g4b_ambitos(clave text, cifra integer, items jsonb);
grant all on g4b_detalle, g4b_pulso, g4b_ambitos to authenticated;

select pg_temp.afirmar(v1 is not null and sup1 is not null and ajeno is not null and sup2 is not null and fuera is not null
  and inactivo is not null and coordinador is not null and gerente is not null and global is not null,
  'faltan actores sintéticos (v1, sup1, ajeno, sup2, fuera, inactivo, coordinador, gerente, global)') from g4b_actores;

-- Fixtures (sólo aquí se desactivan triggers de usuario; se restauran enseguida).
-- El detalle y el pulso consultan el control SLA: en un banco sin él, una fila en
-- «observacion» (sin política, como el modo del demo). En producción ya existe.
alter table crm.sla_operacion_control disable trigger user;
insert into crm.sla_operacion_control(id, modo, revision, cambiado_en, cambiado_por)
select true, 'observacion', 0, now(), gerente from g4b_actores
where not exists (select 1 from crm.sla_operacion_control);
alter table crm.sla_operacion_control enable trigger user;
alter table crm.equipo disable trigger user;
-- Supervisores anidados: sup2 cuelga de sup1. En el pulso, el analista de sup2 sigue en el
-- equipo de sup2 (supervisor activo MÁS CERCANO); en el árbol de sup1 también está.
update crm.equipo set supervisor_id = (select sup1 from g4b_actores) where perfil_id = (select sup2 from g4b_actores);
alter table crm.equipo enable trigger user;
alter table crm.tareas disable trigger user;
update crm.tareas set activo = false
where tipo = 'reunion' and creado_en >= (select ini - interval '1 day' from g4b_actores) and creado_en < (select fin + interval '1 day' from g4b_actores);
create temporary table g4b_citas(titulo text primary key, id uuid not null default gen_random_uuid(), dentro boolean not null);
grant select on g4b_citas to authenticated, anon;
insert into g4b_citas(titulo, dentro) values
  ('G4B V1 BORDE INICIO', true), ('G4B V1 EMPATE A', true), ('G4B V1 EMPATE B', true),
  ('G4B V1 BORDE FIN', true), ('G4B V1 COMPLETADA', true), ('G4B V1 DIA SIGUIENTE', false),
  ('G4B V1 DIA ANTERIOR', false), ('G4B V1 INACTIVA', false), ('G4B AJENO 1', true), ('G4B AJENO 2', true),
  ('G4B FUERA', true), ('G4B INACTIVO', true), ('G4B SIN AUTOR', true), ('G4B V1 REPROGRAMADA', true);
-- Cierres coherentes con tareas_cierre_reunion_coherente (resultado o motivo según el estado).
insert into crm.tareas(id, perfil_id, vendedor_id, tipo, titulo, vence_en, creado_por, creado_en, estado, activo,
  modalidad_reunion, resultado_reunion, motivo_no_realizada, cancelada_por)
select c.id, coalesce(x.vendedor, a.gerente), x.vendedor, 'reunion', c.titulo, now() + interval '2 days', a.gerente, x.creado, x.estado, x.activo,
  'sin_clasificar', case x.estado when 'completada' then 'interesado' end,
  case x.estado when 'no_show' then 'cliente_no_asistio' when 'cancelada' then 'cancelada_cliente' when 'reprogramada' then 'reprogramada' end,
  case x.estado when 'cancelada' then 'sistema' end
from g4b_actores a
cross join lateral (values
  ('G4B V1 BORDE INICIO', a.v1, a.ini, 'pendiente', true),
  ('G4B V1 EMPATE A', a.v1, a.ini + interval '2 hours', 'pendiente', true),
  ('G4B V1 EMPATE B', a.v1, a.ini + interval '2 hours', 'pendiente', true),
  ('G4B V1 BORDE FIN', a.v1, a.fin - interval '1 microsecond', 'pendiente', true),
  ('G4B V1 COMPLETADA', a.v1, a.ini + interval '4 hours', 'completada', true),
  ('G4B V1 DIA SIGUIENTE', a.v1, a.fin, 'pendiente', true),
  ('G4B V1 DIA ANTERIOR', a.v1, a.ini - interval '1 microsecond', 'pendiente', true),
  ('G4B V1 INACTIVA', a.v1, a.ini + interval '3 hours', 'pendiente', false),
  ('G4B AJENO 1', a.ajeno, a.ini + interval '1 hour', 'pendiente', true),
  ('G4B AJENO 2', a.ajeno, a.ini + interval '5 hours', 'cancelada', true),
  ('G4B FUERA', a.fuera, a.ini + interval '6 hours', 'pendiente', true),
  ('G4B INACTIVO', a.inactivo, a.ini + interval '7 hours', 'no_show', true),
  ('G4B SIN AUTOR', null::uuid, a.ini + interval '8 hours', 'pendiente', true),
  ('G4B V1 REPROGRAMADA', a.v1, a.ini + interval '10 hours', 'reprogramada', true)
) as x(titulo, vendedor, creado, estado, activo)
join g4b_citas c on c.titulo = x.titulo;
-- Postventa: una cita de v1 sobre un inversionista del analista «fuera». Lista y cifra
-- comparten la RLS efectiva, sea cual sea su visibilidad para cada rol.
alter table crm.inversionistas disable trigger user;
insert into crm.inversionistas(id, responsable_relacion_id, creado_por) select inversionista, fuera, gerente from g4b_actores;
alter table crm.inversionistas enable trigger user;
insert into crm.tareas(inversionista_id, postventa_revision, vendedor_id, tipo, titulo, vence_en, creado_por, creado_en, modalidad_reunion)
select inversionista, 1, v1, 'reunion', 'G4B V1 POSTVENTA', now() + interval '2 days', v1, ini + interval '9 hours', 'sin_clasificar' from g4b_actores;
alter table crm.tareas enable trigger user;

-- 1. Gerencia: la lista de cada analista es la cifra del detalle y de gestion_diaria_llamadas.
select pg_temp.como(gerente) from g4b_actores;
set local role authenticated;
insert into g4b_detalle
select (f->>'analista_id')::uuid, (f#>>'{marcador,citas_agendadas}')::integer
from g4b_actores a, jsonb_array_elements(crm.gestion_diaria_equipo_fn(a.dia, null)->'equipo') f;
select pg_temp.afirmar(exists (select 1 from g4b_detalle), 'el detalle de Gerencia trae analistas');
select pg_temp.afirmar(jsonb_array_length(pg_temp.lista(a.dia, 'analista', d.analista)) = d.citas,
  format('Gerencia: lista del analista %s = cifra del detalle (%s)', d.analista, d.citas))
from g4b_actores a, g4b_detalle d;
-- Los bordes: entra el primer instante del día y el último; salen el día anterior y el siguiente.
select pg_temp.afirmar(
  (select array_agg(c.titulo order by c.titulo) from g4b_citas c where c.id = any(pg_temp.ids(pg_temp.lista(a.dia, 'analista', a.v1))))
  @> array['G4B V1 BORDE FIN', 'G4B V1 BORDE INICIO', 'G4B V1 COMPLETADA', 'G4B V1 EMPATE A', 'G4B V1 EMPATE B']
  and not exists (select 1 from g4b_citas c where not c.dentro and c.id = any(pg_temp.ids(pg_temp.lista(a.dia, 'analista', a.v1)))),
  'bordes del día Lima, estados sin filtrar e inactiva fuera') from g4b_actores a;
-- Empate de creado_en: el orden lo decide el id.
select pg_temp.afirmar((select array_agg(x->>'id' order by n) from jsonb_array_elements(pg_temp.lista(a.dia, 'analista', a.v1)) with ordinality e(x, n)
    where x->>'id' in (select id::text from g4b_citas where titulo like 'G4B V1 EMPATE%'))
  = (select array_agg(id::text order by id) from g4b_citas where titulo like 'G4B V1 EMPATE%'), 'empate ordenado por id') from g4b_actores a;

-- 2. Gerencia: equipo, «fuera» y operación PARTEN la operación y son la cifra del pulso.
insert into g4b_pulso select crm.gestion_diaria_pulso_fn(dia) from g4b_actores;
insert into g4b_ambitos
select e->>'clave', (e#>>'{metricas,citas_agendadas}')::integer,
  pg_temp.lista(a.dia, case when e->>'clave' = 'fuera' then 'fuera' else 'equipo' end,
    case when e->>'clave' = 'fuera' then null else (e->>'clave')::uuid end, 3) items
from g4b_actores a, g4b_pulso, jsonb_array_elements(p->'equipos') e;
select pg_temp.afirmar(jsonb_array_length(items) = cifra, format('ámbito %s: lista %s = cifra del pulso %s', clave, jsonb_array_length(items), cifra))
from g4b_ambitos;
select pg_temp.afirmar(pg_temp.ids(pg_temp.lista(a.dia, 'operacion', null, 5))
    = (select coalesce(array_agg(i order by i), '{}') from g4b_ambitos, unnest(pg_temp.ids(items)) i)
  and (select cardinality(array_agg(i)) from g4b_ambitos, unnest(pg_temp.ids(items)) i)
    = (select cardinality(array_agg(distinct i)) from g4b_ambitos, unnest(pg_temp.ids(items)) i)
  and jsonb_array_length(pg_temp.lista(a.dia, 'operacion', null, 5)) = (p#>>'{actual,citas_agendadas}')::integer,
  'los equipos y «fuera» parten la operación, sin solaparse, y la operación es la cifra del pulso')
from g4b_actores a, g4b_pulso;
select pg_temp.afirmar(jsonb_array_length(pg_temp.lista(a.dia, 'operacion', null, 50)) = (
    select coalesce(sum(l.citas_agendadas), 0)::integer from private.gestion_diaria_llamadas(a.ini, a.fin,
      (select array_agg(x.id) from private.gestion_diaria_pulso_autores(a.ini, a.fin) x)) l),
  'la operación es la cifra de gestion_diaria_llamadas sobre los autores del pulso') from g4b_actores a;
-- «fuera»: sin autor, autor inactivo y analista sin supervisor; nunca los de un equipo.
select pg_temp.afirmar(pg_temp.ids(items) @> (select array_agg(id) from g4b_citas where titulo in ('G4B FUERA', 'G4B INACTIVO', 'G4B SIN AUTOR'))
  and not (pg_temp.ids(items) && (select array_agg(id) from g4b_citas where titulo like 'G4B V1%' or titulo like 'G4B AJENO%')),
  'composición de «fuera»') from g4b_ambitos where clave = 'fuera';
-- Anidados: las citas del analista de sup2 son de sup2 (el más cercano), no de sup1.
select pg_temp.afirmar(
  pg_temp.ids((select items from g4b_ambitos where clave = a.sup2::text)) @> (select array_agg(id) from g4b_citas where titulo like 'G4B AJENO%')
  and not (pg_temp.ids((select items from g4b_ambitos where clave = a.sup1::text)) && (select array_agg(id) from g4b_citas where titulo like 'G4B AJENO%')),
  'supervisores anidados: gana el supervisor activo más cercano') from g4b_actores a;
-- Contrato de cada fila.
select pg_temp.afirmar(not exists (select 1 from jsonb_array_elements(pg_temp.lista(a.dia, 'operacion', null, 50)) x
  where x->>'estado' not in ('pendiente', 'completada', 'cancelada', 'no_show', 'reprogramada') or x->>'vence_en' is null or x->>'creado_en' is null
    or ((x->>'lead_id') is null) <> ((x->>'lead_nombre') is null)),
  'forma de cada fila') from g4b_actores a;
reset role;

-- 3. Supervisión: sólo el ámbito «analista» de su árbol, y su lista es su cifra.
select pg_temp.como(sup1) from g4b_actores;
set local role authenticated;
select pg_temp.afirmar(jsonb_array_length(pg_temp.lista(a.dia, 'analista', (f->>'analista_id')::uuid)) = (f#>>'{marcador,citas_agendadas}')::integer,
  format('Supervisión: lista de %s = cifra de su detalle', f->>'analista_id'))
from g4b_actores a, jsonb_array_elements(crm.gestion_diaria_equipo_fn(a.dia, null)->'equipo') f;
select pg_temp.afirmar(jsonb_array_length(pg_temp.lista(a.dia, 'analista', a.ajeno)) = 2, 'el árbol de sup1 incluye al analista de sup2 anidado') from g4b_actores a;
select pg_temp.denegada(format('select crm.gestion_diaria_citas_fn(%L, %L, %L)', a.dia, x.ambito, x.id))
from g4b_actores a, lateral (values ('analista', a.fuera), ('analista', a.inactivo), ('analista', a.nadie),
  ('equipo', a.sup1), ('fuera', null::uuid), ('operacion', null::uuid)) x(ambito, id);
reset role;
select pg_temp.como(sup2) from g4b_actores;
set local role authenticated;
select pg_temp.denegada(format('select crm.gestion_diaria_citas_fn(%L, %L, %L)', dia, 'analista', v1)) from g4b_actores;
reset role;

-- 4. Gerencia: ámbitos que no existen o no le tocan; parámetros inválidos.
select pg_temp.como(gerente) from g4b_actores;
set local role authenticated;
select pg_temp.denegada(format('select crm.gestion_diaria_citas_fn(%L, %L, %L)', a.dia, x.ambito, x.id))
from g4b_actores a, lateral (values ('equipo', a.v1), ('equipo', a.nadie), ('analista', a.inactivo), ('analista', a.nadie)) x(ambito, id);
select pg_temp.denegada(format('select crm.gestion_diaria_citas_fn(%L, %L, %L, %s, %L, %L)', x.dia, x.ambito, x.id, x.limite, x.de, x.id2), '22023')
from g4b_actores a, lateral (values
  (a.dia, 'analista', null::uuid, 25, null::timestamptz, null::uuid), (a.dia, 'equipo', null, 25, null, null),
  (a.dia, 'fuera', a.v1, 25, null, null), (a.dia, 'operacion', a.v1, 25, null, null), (a.dia, 'otro', null, 25, null, null),
  (null::date, 'operacion', null, 25, null, null), (a.dia + 2, 'operacion', null, 25, null, null),
  (a.dia - 366, 'operacion', null, 25, null, null), (a.dia, 'operacion', null, 0, null, null),
  (a.dia, 'operacion', null, 101, null, null), (a.dia, 'operacion', null, 25, now(), null),
  (a.dia, 'operacion', null, 25, 'infinity'::timestamptz, gen_random_uuid())
) x(dia, ambito, id, limite, de, id2);
select pg_temp.denegada(format('select crm.gestion_diaria_citas_fn(%L, null)', dia), '22023') from g4b_actores;
reset role;

-- 5. Sin esta puerta: analista, coordinación, lector global y un uid sin rol (puerta y núcleo).
do $$ declare actor uuid; begin
  for actor in select unnest(array[v1, coordinador, global, nadie]) from g4b_actores loop
    perform pg_temp.como(actor);
    execute 'set local role authenticated';
    perform pg_temp.denegada(format('select crm.gestion_diaria_citas_fn(%L, %L, %L)', (select dia from g4b_actores), 'analista', (select v1 from g4b_actores)));
    perform pg_temp.denegada(format('select crm.gestion_diaria_citas_fn(%L, %L)', (select dia from g4b_actores), 'operacion'));
    perform pg_temp.denegada(format('select private.gestion_diaria_citas_core(%L, %L, null, 25, null, null)', (select dia from g4b_actores), 'operacion'));
    execute 'reset role';
  end loop;
end $$;
set local role anon;
select pg_temp.denegada(format('select crm.gestion_diaria_citas_fn(%L, %L)', dia, 'operacion')) from g4b_actores;
reset role;

-- 6. El paraguas ejecuta el gate nuevo.
select pg_temp.afirmar(private.assert_gestion_diaria_citas() like 'OK:%' and private.assert_gestion_diaria() like '%OK: citas G4b%', 'gate G4b enchufado');
select 'G4B_OK' as resultado;
rollback;
```

## Front (diff frente a main 249f84d4)
```diff
diff --git a/CRM-Avance-Corp/app/src/components/gestion-diaria/citas-agendadas.test.tsx b/CRM-Avance-Corp/app/src/components/gestion-diaria/citas-agendadas.test.tsx
new file mode 100644
index 00000000..b13886bb
--- /dev/null
+++ b/CRM-Avance-Corp/app/src/components/gestion-diaria/citas-agendadas.test.tsx
@@ -0,0 +1,75 @@
+// G4b: la lista exacta de citas agendadas. Filas limpias (hora de agenda, estado, lead que
+// abre su ficha, analista cuando hay varios, cuándo es la cita) y estados que se dicen.
+import { createRef } from 'react'
+import { describe, expect, it, vi, beforeEach } from 'vitest'
+import { fireEvent, render, screen, within } from '@testing-library/react'
+import type { CitaAgendada } from '@/lib/gestion-diaria-citas'
+import { CrmApiError } from '@/data/crm-api'
+
+const dobles = vi.hoisted(() => ({ lista: {} as Record<string, unknown>, abrirLead: vi.fn() }))
+vi.mock('@/data/gestion-diaria-citas-queries', () => ({ useCitasGestion: () => dobles.lista }))
+vi.mock('@/lib/store-context', () => ({ usePanelesActions: () => ({ abrirLead: dobles.abrirLead }) }))
+const { CitasAgendadas } = await import('./citas-agendadas')
+
+const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`
+const cita = (n: number, extra: Partial<CitaAgendada> = {}): CitaAgendada => ({
+  id: id(n), vendedor_id: id(90), vendedor_nombre: 'ANALISTA UNO', lead_id: id(200 + n), lead_nombre: `LEAD ${n}`,
+  vence_en: '2026-09-26T15:00:00.000Z', estado: 'pendiente', creado_en: '2026-09-24T19:32:00.000Z', ...extra,
+})
+const base = { items: [] as CitaAgendada[], total: 0, consultadoEn: '2026-09-24T22:00:00.000Z', cargando: false, enVuelo: false,
+  error: null as unknown, sinPermiso: false, hayMas: false, cargarMas: vi.fn(), recargar: vi.fn() }
+function montar(extra: Partial<typeof base>, mostrarAnalista = true) {
+  dobles.lista = { ...base, ...extra }
+  const revalidar = vi.fn()
+  render(<CitasAgendadas dia="2026-09-24" esHoy ambito="operacion" id={null} mostrarAnalista={mostrarAnalista} visible actualizacion={0}
+    revalidar={revalidar} encabezado={createRef<HTMLHeadingElement>()} />)
+  return { revalidar }
+}
+beforeEach(() => { vi.clearAllMocks() })
+
+describe('CitasAgendadas', () => {
+  it('cada fila: hora de agenda, estado, lead que abre su ficha, analista y cuándo es la cita', () => {
+    montar({ items: [cita(1), cita(2, { estado: 'no_show', lead_id: null, lead_nombre: null, vendedor_nombre: null }), cita(3, { estado: 'reprogramada' })], total: 3 })
+    expect(screen.getByRole('status')).toHaveTextContent('3 citas agendadas hoy')
+    const filas = within(screen.getByRole('list', { name: 'Citas agendadas' })).getAllByRole('listitem')
+    expect(filas).toHaveLength(3)
+    expect(filas[2]).toHaveTextContent('Reprogramada')
+    expect(filas[0]).toHaveTextContent('Agendada a las 14:32')
+    expect(filas[0]).toHaveTextContent('Pendiente')
+    expect(filas[0]).toHaveTextContent('· ANALISTA UNO')
+    expect(filas[0]).toHaveTextContent(/Cita: .*10:00/)
+    fireEvent.click(within(filas[0]!).getByRole('button', { name: 'LEAD 1' }))
+    expect(dobles.abrirLead).toHaveBeenCalledWith(id(201))
+    expect(filas[1]).toHaveTextContent('No asistió')
+    expect(filas[1]).toHaveTextContent('Lead no visible')
+    expect(filas[1]).toHaveTextContent('Sin analista')
+  })
+  it('en la ficha de un analista no repite su nombre en cada fila', () => {
+    montar({ items: [cita(1)], total: 1 }, false)
+    expect(screen.getByRole('listitem')).not.toHaveTextContent('ANALISTA UNO')
+    expect(screen.getByRole('status')).toHaveTextContent('1 cita agendada hoy')
+  })
+  it('cero es una lista vacía que se dice, no un error', () => {
+    montar({ total: 0 })
+    expect(screen.getByRole('status')).toHaveTextContent('Ninguna cita agendada hoy.')
+    expect(screen.queryByRole('list')).not.toBeInTheDocument()
+  })
+  it('un error sin filas no se presenta como «ninguna cita» y ofrece reintentar', () => {
+    const recargar = vi.fn()
+    montar({ error: new Error('sin red'), total: null as unknown as number, recargar })
+    expect(screen.getByRole('alert')).toHaveTextContent('Esto no significa que no haya citas')
+    fireEvent.click(screen.getByRole('button', { name: 'Reintentar' }))
+    expect(recargar).toHaveBeenCalledOnce()
+  })
+  it('sin permiso retira la lista y avisa a la pantalla', () => {
+    const { revalidar } = montar({ sinPermiso: true, error: new CrmApiError('revocado', '42501') })
+    expect(screen.getByRole('alert')).toHaveTextContent('Ya no tienes autorización')
+    expect(revalidar).toHaveBeenCalledOnce()
+  })
+  it('«Ver más» pide la página siguiente', () => {
+    const cargarMas = vi.fn()
+    montar({ items: [cita(1)], total: 30, hayMas: true, cargarMas })
+    fireEvent.click(screen.getByRole('button', { name: 'Ver más' }))
+    expect(cargarMas).toHaveBeenCalledOnce()
+  })
+})
diff --git a/CRM-Avance-Corp/app/src/components/gestion-diaria/citas-agendadas.tsx b/CRM-Avance-Corp/app/src/components/gestion-diaria/citas-agendadas.tsx
new file mode 100644
index 00000000..46d68a91
--- /dev/null
+++ b/CRM-Avance-Corp/app/src/components/gestion-diaria/citas-agendadas.tsx
@@ -0,0 +1,102 @@
+// G4b (27/09/2026): la lista EXACTA de «Citas agendadas» —las citas CREADAS ese día—,
+// la misma definición que la cifra. Filas limpias como el registro compacto: a qué hora
+// se agendó, el estado, el lead (abre su ficha), el analista cuando el ámbito tiene
+// varios y cuándo es la cita. El título lo pone quien la aloja.
+import { useEffect, useEffectEvent, type JSX, type RefObject } from 'react'
+import { useCitasGestion } from '@/data/gestion-diaria-citas-queries'
+import type { AmbitoCitas, EstadoCita } from '@/lib/gestion-diaria-citas'
+import { horaLimaDe } from '@/lib/gestion-diaria-analista'
+import { usePanelesActions } from '@/lib/store-context'
+import { Badge } from '@/components/ui/badge'
+import { PanelCargando } from '@/components/common/estado-panel'
+import { cn } from '@/lib/utils'
+import { BotonVerMasCompacto } from './registro-actividad'
+import { FOCO } from './estilos-gestion'
+
+const CUANDO = new Intl.DateTimeFormat('es-PE', { weekday: 'short', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit', hour12: false, timeZone: 'America/Lima' })
+const ESTADO: Record<EstadoCita, { texto: string; color: string }> = {
+  pendiente: { texto: 'Pendiente', color: 'var(--primary)' },
+  completada: { texto: 'Realizada', color: 'var(--accent-press)' },
+  cancelada: { texto: 'Cancelada', color: 'var(--muted-foreground-strong)' },
+  no_show: { texto: 'No asistió', color: 'var(--warning-text)' },
+  reprogramada: { texto: 'Reprogramada', color: 'var(--muted-foreground-strong)' },
+}
+const plural = (n: number, uno: string, varios: string) => `${n} ${n === 1 ? uno : varios}`
+
+export function CitasAgendadas({ dia, esHoy, ambito, id, mostrarAnalista, visible, actualizacion, revalidar, encabezado }: {
+  dia: string
+  esHoy: boolean
+  ambito: AmbitoCitas
+  id: string | null
+  /** Con varios analistas en el ámbito, cada fila dice de quién es. */
+  mostrarAnalista: boolean
+  visible: boolean
+  actualizacion: number
+  /** Un 42501 retira la vista entera, como en el resto de Gestión Diaria. */
+  revalidar: () => void
+  /** El título al que vuelve el foco si «Ver más» desaparece con el foco dentro. */
+  encabezado: RefObject<HTMLHeadingElement | null>
+}): JSX.Element {
+  const lista = useCitasGestion(dia, ambito, id, visible, actualizacion)
+  const { abrirLead } = usePanelesActions()
+  const revocar = useEffectEvent(revalidar)
+  useEffect(() => { if (lista.sinPermiso) revocar() }, [lista.sinPermiso])
+  const cuando = esHoy ? 'hoy' : 'ese día'
+
+  if (lista.sinPermiso) {
+    return <p role="alert" className="text-[13px] font-semibold text-[var(--destructive-text)]">Ya no tienes autorización para ver estas citas.</p>
+  }
+  if (lista.error && lista.items.length === 0) {
+    return (
+      <div role="alert" className="space-y-2 text-[13px]">
+        <p className="font-semibold text-primary">No se pudo cargar la lista de citas. Esto no significa que no haya citas.</p>
+        <button type="button" onClick={() => void lista.recargar()} aria-disabled={lista.enVuelo}
+          className={cn('inline-flex h-9 cursor-pointer items-center rounded-[10px] px-3 text-[13px] font-bold text-[var(--accent-press)] hover:bg-accent/10 aria-disabled:opacity-50', FOCO)}>
+          Reintentar
+        </button>
+      </div>
+    )
+  }
+  if (lista.cargando) return <PanelCargando filas={3} />
+  return (
+    <div className="space-y-1">
+      <p role="status" className="text-[12.5px] text-[var(--muted-foreground-strong)]">
+        {lista.total === 0 ? `Ninguna cita agendada ${cuando}.` : `${plural(lista.total ?? lista.items.length, 'cita agendada', 'citas agendadas')} ${cuando}`}
+        {lista.consultadoEn && lista.total !== 0 && <> · consulta {horaLimaDe(lista.consultadoEn)}</>}
+      </p>
+      {lista.items.length > 0 && (
+        // oxlint-disable-next-line jsx-a11y/no-redundant-roles
+        <ol role="list" aria-label="Citas agendadas" aria-busy={lista.enVuelo}>
+          {lista.items.map((c) => (
+            <li key={c.id} className="flex gap-3 border-b border-muted py-2.5">
+              <time dateTime={c.creado_en} className="w-10 shrink-0 pt-0.5 text-[13px] font-bold tabular-nums text-foreground/80">
+                <span className="sr-only">Agendada a las </span>{horaLimaDe(c.creado_en)}
+              </time>
+              <div className="min-w-0 flex-1 space-y-1">
+                <div className="flex flex-wrap items-center gap-2">
+                  <Badge className="min-h-[22px] py-0 text-[11.5px]" color={ESTADO[c.estado].color}>{ESTADO[c.estado].texto}</Badge>
+                  {c.lead_id && c.lead_nombre
+                    ? <button type="button" onClick={() => void abrirLead(c.lead_id!)}
+                      className={cn('cursor-pointer rounded-md text-left text-sm font-bold text-primary underline-offset-2 hover:underline', FOCO)}>{c.lead_nombre}</button>
+                    : <span className="text-sm font-semibold text-[var(--muted-foreground-strong)]">Lead no visible</span>}
+                  {mostrarAnalista && <span className="text-[12.5px] font-semibold text-[var(--muted-foreground-strong)]">· {c.vendedor_nombre ?? 'Sin analista'}</span>}
+                </div>
+                <p className="text-[12.5px] text-foreground/80">Cita: <time dateTime={c.vence_en}>{CUANDO.format(new Date(c.vence_en))}</time></p>
+              </div>
+            </li>
+          ))}
+        </ol>
+      )}
+      {lista.error && lista.items.length > 0 && (
+        <p role="alert" className="text-[13px] font-semibold text-[var(--warning-text)]">No se pudo traer la siguiente página. Se conservan las ya consultadas.</p>
+      )}
+      {(lista.hayMas || (lista.error && lista.items.length > 0)) && (
+        <div className="flex justify-center pt-2">
+          <BotonVerMasCompacto ocupado={lista.enVuelo} error={Boolean(lista.error)}
+            onPulsar={lista.error ? () => void lista.recargar() : () => void lista.cargarMas()}
+            alSalirConFoco={() => encabezado.current?.focus({ preventScroll: true })} />
+        </div>
+      )}
+    </div>
+  )
+}
diff --git a/CRM-Avance-Corp/app/src/components/gestion-diaria/panel-analista-supervisor.tsx b/CRM-Avance-Corp/app/src/components/gestion-diaria/panel-analista-supervisor.tsx
index f9541dd2..a5ba1534 100644
--- a/CRM-Avance-Corp/app/src/components/gestion-diaria/panel-analista-supervisor.tsx
+++ b/CRM-Avance-Corp/app/src/components/gestion-diaria/panel-analista-supervisor.tsx
@@ -6,6 +6,7 @@ import { Button } from '@/components/ui/button'
 import { Tabs } from '@/components/ui/tabs'
 import { RegistroActividad } from './registro-actividad'
 import { PendientesSupervisor } from './pendientes-supervisor'
+import { CitasAgendadas } from './citas-agendadas'
 import { ResumenAnalista } from './resumen-analista'
 import { UltimasGestionesSupervisor } from './ultimas-gestiones-supervisor'
 import type { FilaEquipoPresentada } from '@/lib/gestion-diaria-equipo'
@@ -21,7 +22,7 @@ export interface SeleccionSupervisor {
   analista: string | null; nombre: string | null; apertura: number; pestana: PestanaRegistro; enfocar: boolean
   origen?: 'automatica' | 'usuario' | 'aviso' | undefined
 }
-type PestanaPanel = 'resumen' | 'registro' | 'pendientes'
+type PestanaPanel = 'resumen' | 'registro' | 'pendientes' | 'citas'
 
 const BOTON_ICONO = 'grid size-9 shrink-0 cursor-pointer place-items-center rounded-[10px] text-[var(--muted-foreground-strong)] transition-colors hover:bg-muted hover:text-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring pointer-coarse:size-11'
 
@@ -89,21 +90,28 @@ function ContenidoSeleccionado({ seleccion, fila, dia, minimo, tituloRef, oculta
   const [pestana, setPestana] = useState<PestanaPanel>(equipo || seleccion.enfocar ? 'registro' : 'resumen')
   const [registro, setRegistro] = useState<{ pestana: PestanaRegistro; apertura: number } | null>(equipo || seleccion.enfocar ? { pestana: seleccion.pestana, apertura: 0 } : null)
   const [pendientes, setPendientes] = useState<{ soloVencidas: boolean; apertura: number; enfocar: boolean } | null>(null)
+  const [citas, setCitas] = useState<{ apertura: number } | null>(null)
   const tituloRegistro = useRef<HTMLHeadingElement>(null)
+  const tituloCitas = useRef<HTMLHeadingElement>(null)
   const cuerpoResumen = useRef<HTMLDivElement>(null)
   const alInicio = () => cuerpoResumen.current?.closest('[role=tabpanel]')?.scrollTo?.({ top: 0 })
   const [focoRegistro, setFocoRegistro] = useState(0)
+  const [focoCitas, setFocoCitas] = useState(0)
   useLayoutEffect(() => {
     if (seleccion.enfocar) tituloRef.current?.focus({ preventScroll: true })
   }, [seleccion.enfocar, tituloRef])
   useLayoutEffect(() => {
     if (focoRegistro) tituloRegistro.current?.focus({ preventScroll: true })
   }, [focoRegistro])
+  useLayoutEffect(() => {
+    if (focoCitas) tituloCitas.current?.focus({ preventScroll: true })
+  }, [focoCitas])
   const cambiar = (valor: PestanaPanel) => {
     alInicio()
     setPestana(valor)
     if (valor === 'registro' && !registro) setRegistro({ pestana: 'todo', apertura: 0 })
     if (valor === 'pendientes' && !pendientes) setPendientes({ soloVencidas: false, apertura: 0, enfocar: false })
+    if (valor === 'citas' && !citas) setCitas({ apertura: 0 })
   }
   const abrirRegistro = (inicial: PestanaRegistro) => {
     alInicio()
@@ -116,12 +124,19 @@ function ContenidoSeleccionado({ seleccion, fila, dia, minimo, tituloRef, oculta
     setPendientes(p => ({ soloVencidas, apertura: (p?.apertura ?? 0) + 1, enfocar: true }))
     setPestana('pendientes')
   }
+  // G4b: «Citas agendadas» abre su lista exacta, como «Ver pendientes» abre la suya.
+  const abrirCitas = () => {
+    alInicio()
+    setCitas((c) => ({ apertura: (c?.apertura ?? 0) + 1 }))
+    setPestana('citas')
+    setFocoCitas((n) => n + 1)
+  }
   const cuerpo = 'min-w-0 px-5 py-4 [overflow-wrap:anywhere]'
   const contenido = <>
     <div ref={cuerpoResumen} className={cn(cuerpo, 'space-y-5')} hidden={pestana !== 'resumen'} inert={pestana !== 'resumen'}>
       {!fila || minimo === undefined ? <p role="status" className="text-[13px] text-[var(--muted-foreground-strong)]">El resumen no está disponible. El registro conserva su consulta independiente.</p>
         : <ResumenAnalista fila={fila} dia={dia} minimo={minimo} esHoy={esHoy} ahora={ahora}
-          abrirLlamadas={() => abrirRegistro('llamadas')} abrirPendientes={conPendientes ? abrirPendientes : undefined} />}
+          abrirLlamadas={() => abrirRegistro('llamadas')} abrirPendientes={conPendientes ? abrirPendientes : undefined} abrirCitas={abrirCitas} />}
       {seleccion.analista !== null && <>
         <UltimasGestionesSupervisor analista={seleccion.analista} dia={dia} visible={pestana === 'resumen'} actualizacion={actualizacion} revalidar={revalidar} silencioso={silencioso} />
         <div className="space-y-2">
@@ -150,6 +165,15 @@ function ContenidoSeleccionado({ seleccion, fila, dia, minimo, tituloRef, oculta
         visible={pestana === 'pendientes'} soloVencidasInicial={pendientes.soloVencidas} apertura={pendientes.apertura}
         enfocar={pendientes.enfocar} actualizacion={actualizacion} revalidar={revalidar} />}
     </div>
+    <div className={cuerpo} hidden={pestana !== 'citas'} inert={pestana !== 'citas'}>
+      {citas && seleccion.analista !== null && <section aria-label="Citas agendadas del analista" className="space-y-2">
+        <h4 ref={tituloCitas} tabIndex={-1} className="rounded-md text-[15px] font-extrabold text-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring">
+          {esHoy ? 'Citas agendadas hoy' : `Citas agendadas el ${FECHA_TITULO.format(new Date(`${dia}T12:00:00-05:00`))}`}
+        </h4>
+        <CitasAgendadas key={citas.apertura} dia={dia} esHoy={esHoy} ambito="analista" id={seleccion.analista} mostrarAnalista={false}
+          visible={pestana === 'citas'} actualizacion={actualizacion} revalidar={revalidar} encabezado={tituloCitas} />
+      </section>}
+    </div>
   </>
   return <>
     {oculta && <div className="flex shrink-0 flex-wrap items-center justify-between gap-2 bg-muted px-5 py-1.5 text-[13px]">La selección está fuera de los filtros.
@@ -158,7 +182,7 @@ function ContenidoSeleccionado({ seleccion, fila, dia, minimo, tituloRef, oculta
         así el texto tras el último control se alcanza sin ratón. */}
     {equipo ? <div className="ac-scroll min-h-0 flex-1 overflow-y-auto">{contenido}</div>
       : <Tabs etiqueta="Detalle del analista" variante="subrayado" valor={pestana} onCambio={cambiar}
-        pestanas={[{ valor: 'resumen', etiqueta: 'Resumen' }, { valor: 'registro', etiqueta: 'Registro' }, ...(conPendientes ? [{ valor: 'pendientes' as const, etiqueta: 'Pendientes' }] : [])]}
+        pestanas={[{ valor: 'resumen', etiqueta: 'Resumen' }, { valor: 'registro', etiqueta: 'Registro' }, ...(conPendientes ? [{ valor: 'pendientes' as const, etiqueta: 'Pendientes' }] : []), { valor: 'citas', etiqueta: 'Citas' }]}
         className="flex min-h-0 flex-1 flex-col space-y-0 [&>[role=tablist]]:gap-[22px] [&>[role=tablist]]:px-5 [&>[role=tablist]>[role=tab]]:min-h-[42px] [&>[role=tablist]>[role=tab]]:text-sm pointer-coarse:[&>[role=tablist]>[role=tab]]:min-h-11"
         clasePanel="ac-scroll min-h-0 flex-1 overflow-y-auto focus-visible:!-outline-offset-2">{contenido}</Tabs>}
   </>
diff --git a/CRM-Avance-Corp/app/src/components/gestion-diaria/panel-operacion-gerencia.tsx b/CRM-Avance-Corp/app/src/components/gestion-diaria/panel-operacion-gerencia.tsx
index 9c9a215d..18e6d14a 100644
--- a/CRM-Avance-Corp/app/src/components/gestion-diaria/panel-operacion-gerencia.tsx
+++ b/CRM-Avance-Corp/app/src/components/gestion-diaria/panel-operacion-gerencia.tsx
@@ -5,7 +5,7 @@
 // analistas activos, y lo dice (revisión Codex del plan).
 import { useRef, type JSX, type ReactNode, type RefObject } from 'react'
 import { Title as TituloDialogo } from '@radix-ui/react-dialog'
-import { ChevronRight, ClipboardList, Maximize2, Minimize2, UserX, Users, X } from 'lucide-react'
+import { CalendarCheck, ChevronRight, ClipboardList, Maximize2, Minimize2, UserX, Users, X } from 'lucide-react'
 import { Avatar } from '@/components/ui/avatar'
 import { cifraPulso, type EquipoPulso, type PulsoGerencia } from '@/lib/gestion-diaria-pulso'
 import { atencionEquipo, barrasEquipo, delEquipo, nombreEquipo, personasSinRegistro, type PresetEquipo } from '@/lib/gestion-diaria-operacion'
@@ -14,12 +14,15 @@ import type { PestanaRegistro } from '@/lib/gestion-diaria'
 import { cn } from '@/lib/utils'
 import { BarrasPorHora } from './barras-por-hora'
 import { RegistroActividad } from './registro-actividad'
+import { CitasAgendadas } from './citas-agendadas'
 import { BOTON_ICONO, CABECERA_FICHA, FICHA, FOCO, TITULO_FICHA } from './estilos-gestion'
 
 export type VistaOperacion =
   | { tipo: 'equipo'; clave: string }
   | { tipo: 'sin_registro' }
   | { tipo: 'registro'; alcance: 'general' | string; pestana: PestanaRegistro; apertura: number }
+  /** G4b: la lista exacta de «Citas agendadas» de la operación, de un equipo o de «fuera». */
+  | { tipo: 'citas'; ambito: 'operacion' | 'equipo' | 'fuera'; clave: string | null; apertura: number }
 
 export type { PresetEquipo } from '@/lib/gestion-diaria-operacion'
 
@@ -55,31 +58,36 @@ export function PanelOperacionGerencia({ id, vista, pulso, detalle, detalleFalli
   actualizacion: number
   revocar: () => void
 }): JSX.Element {
-  const equipo = vista?.tipo === 'equipo' || (vista?.tipo === 'registro' && vista.alcance !== 'general')
-    ? pulso.equipos.find((e) => e.clave === (vista.tipo === 'equipo' ? vista.clave : vista.alcance)) : undefined
+  const claveEquipo = vista?.tipo === 'equipo' ? vista.clave : vista?.tipo === 'registro' && vista.alcance !== 'general' ? vista.alcance
+    : vista?.tipo === 'citas' && vista.ambito !== 'operacion' ? vista.ambito === 'fuera' ? 'fuera' : vista.clave : null
+  const equipo = claveEquipo === null ? undefined : pulso.equipos.find((e) => e.clave === claveEquipo)
   // Si el equipo sale de la consulta, el título (y el nombre de la ventana) no queda vacío (a11y, 27/09).
   const nombre = equipo ? nombreEquipo({ fuera: equipo.clave === 'fuera', nombre: equipo.nombre }) : 'Equipo no disponible'
   const del = equipo ? delEquipo({ fuera: equipo.clave === 'fuera', nombre: equipo.nombre }) : 'del equipo no disponible'
   const titulo = vista === null ? 'Detalle de la operación' : vista.tipo === 'sin_registro' ? 'Sin registro'
-    : vista.tipo === 'registro' ? vista.alcance === 'general' ? 'Registro general' : `Registro ${del}` : nombre
+    : vista.tipo === 'citas' ? 'Citas agendadas'
+      : vista.tipo === 'registro' ? vista.alcance === 'general' ? 'Registro general' : `Registro ${del}` : nombre
   // Como la ficha del supervisor (Miguel, 27/09): un nombre corto arriba y una línea
   // debajo. Se ve el nombre del supervisor; se oye «Detalle del Equipo de …».
   const fuera = equipo?.clave === 'fuera'
   const subtitulo = vista === null ? null : vista.tipo === 'sin_registro'
     ? `${plural(pulso.actual.sin_actividad, 'analista sin ninguna gestión', 'analistas sin ninguna gestión')} ${esHoy ? 'hoy' : 'ese día'}`
     : vista.tipo === 'registro' ? equipo ? nombre : null
-      : equipo ? `${fuera ? '' : 'Equipo de '}${plural(equipo.metricas.analistas_activos, 'analista', 'analistas')}` : null
+      : vista.tipo === 'citas' ? vista.ambito === 'operacion' ? 'Toda la operación' : nombre
+        : equipo ? `${fuera ? '' : 'Equipo de '}${plural(equipo.metricas.analistas_activos, 'analista', 'analistas')}` : null
   return (
     <section id={id} aria-label={vista?.tipo === 'equipo' ? `Detalle ${del}` : titulo} className={FICHA}>
       <header className={CABECERA_FICHA}>
         {vista?.tipo === 'equipo' && equipo ? <Avatar nombre={equipo.nombre} color="var(--accent-press)" relleno className="size-11 text-[15px]" />
           : <span aria-hidden="true" className="grid size-8 shrink-0 place-items-center rounded-full bg-muted text-primary">
-            {vista?.tipo === 'sin_registro' ? <UserX className="size-4" /> : vista?.tipo === 'registro' ? <ClipboardList className="size-4" /> : <Users className="size-4" />}
+            {vista?.tipo === 'sin_registro' ? <UserX className="size-4" /> : vista?.tipo === 'registro' ? <ClipboardList className="size-4" />
+              : vista?.tipo === 'citas' ? <CalendarCheck className="size-4" /> : <Users className="size-4" />}
           </span>}
         <div className="min-w-0 flex-1">
           <TituloDialogo asChild><h3 ref={tituloRef} tabIndex={-1} className={TITULO_FICHA}>
             {vista?.tipo === 'equipo' && equipo ? <><span className="sr-only">{fuera ? 'Detalle del grupo' : 'Detalle del Equipo de'}</span>{' '}{equipo.nombre}</>
-              : vista?.tipo === 'registro' && equipo ? <>Registro del equipo<span className="sr-only">: {nombre}</span></> : titulo}
+              : vista?.tipo === 'registro' && equipo ? <>Registro del equipo<span className="sr-only">: {nombre}</span></>
+                : vista?.tipo === 'citas' ? <>Citas agendadas<span className="sr-only">: {subtitulo}</span></> : titulo}
           </h3></TituloDialogo>
           {subtitulo && <p className="mt-0.5 text-[12.5px] text-[var(--muted-foreground-strong)]">{subtitulo}</p>}
         </div>
@@ -95,6 +103,7 @@ export function PanelOperacionGerencia({ id, vista, pulso, detalle, detalleFalli
             ? <FichaEquipo equipo={equipo} del={del} detalle={detalle} detalleFallido={detalleFallido} esHoy={esHoy} abrirVista={abrirVista} entrarEquipo={entrarEquipo} abrirPersona={abrirPersona} />
             : <p role="status" className="px-5 py-4 text-[13px]">Este equipo ya no aparece en la consulta. Elige otro de la tabla.</p>
             : vista.tipo === 'sin_registro' ? <ListaSinRegistro pulso={pulso} esHoy={esHoy} abrirPersona={abrirPersona} />
+              : vista.tipo === 'citas' ? <CitasOperacion key={`${vista.ambito}:${vista.clave}:${vista.apertura}`} vista={vista} dia={pulso.dia} esHoy={esHoy} actualizacion={actualizacion} revocar={revocar} />
               : <RegistroOperacion key={`${vista.alcance}:${vista.apertura}`} vista={vista} pulso={pulso} equipo={equipo} esHoy={esHoy} actualizacion={actualizacion} revocar={revocar} abrirGeneral={() => abrirVista({ tipo: 'registro', alcance: 'general', pestana: vista.pestana, apertura: vista.apertura + 1 })} />}
       </div>
     </section>
@@ -125,7 +134,8 @@ function FichaEquipo({ equipo: e, del, detalle, detalleFallido, esHoy, abrirVist
         <Cuadro etiqueta="Citas agendadas">
           <span className="block text-[28px] font-extrabold leading-tight tabular-nums text-primary">{m.citas_agendadas}</span>
           <span className="block text-xs text-[var(--muted-foreground-strong)]">{esHoy ? 'hoy' : 'ese día'}</span>
-          <button type="button" onClick={() => entrarEquipo(e.clave, 'citas')} aria-label={`Ver por analista las citas ${del}`} className={ENLACE}>Ver por analista<ChevronRight aria-hidden className="size-3.5" /></button>
+          <button type="button" onClick={() => abrirVista({ tipo: 'citas', ambito: e.clave === 'fuera' ? 'fuera' : 'equipo', clave: e.clave === 'fuera' ? null : e.clave, apertura: Date.now() })}
+            aria-label={`Ver citas agendadas ${del}`} className={ENLACE}>Ver citas<ChevronRight aria-hidden className="size-3.5" /></button>
         </Cuadro>
         <Cuadro etiqueta="Tareas vencidas">
           <span className={cn('block text-[28px] font-extrabold leading-tight tabular-nums', e.tareas_vencidas > 0 ? 'text-[var(--destructive-text)]' : 'text-primary')}>{e.tareas_vencidas}</span>
@@ -217,6 +227,22 @@ function ListaSinRegistro({ pulso, esHoy, abrirPersona }: { pulso: PulsoGerencia
 
 const FECHA_TITULO = new Intl.DateTimeFormat('es-PE', { day: 'numeric', month: 'long', timeZone: 'America/Lima' })
 
+/** G4b: la lista exacta de citas agendadas del ámbito elegido; cada fila dice su analista. */
+function CitasOperacion({ vista, dia, esHoy, actualizacion, revocar }: {
+  vista: Extract<VistaOperacion, { tipo: 'citas' }>; dia: string; esHoy: boolean; actualizacion: number; revocar: () => void
+}): JSX.Element {
+  const titulo = useRef<HTMLHeadingElement>(null)
+  return (
+    <section aria-label="Citas seleccionadas" className="space-y-2 px-5 py-4">
+      <h4 ref={titulo} tabIndex={-1} className={cn('rounded-md text-[15px] font-extrabold text-primary', FOCO)}>
+        {esHoy ? 'Citas agendadas hoy' : `Citas agendadas el ${FECHA_TITULO.format(new Date(`${dia}T12:00:00-05:00`))}`}
+      </h4>
+      <CitasAgendadas dia={dia} esHoy={esHoy} ambito={vista.ambito} id={vista.ambito === 'equipo' ? vista.clave : null} mostrarAnalista
+        visible actualizacion={actualizacion} revalidar={revocar} encabezado={titulo} />
+    </section>
+  )
+}
+
 function RegistroOperacion({ vista, pulso, equipo, esHoy, actualizacion, revocar, abrirGeneral }: {
   vista: Extract<VistaOperacion, { tipo: 'registro' }>; pulso: PulsoGerencia; equipo: EquipoPulso | undefined; esHoy: boolean
   actualizacion: number; revocar: () => void; abrirGeneral: () => void
diff --git a/CRM-Avance-Corp/app/src/components/gestion-diaria/registro-actividad.tsx b/CRM-Avance-Corp/app/src/components/gestion-diaria/registro-actividad.tsx
index b01c6e87..c6711163 100644
--- a/CRM-Avance-Corp/app/src/components/gestion-diaria/registro-actividad.tsx
+++ b/CRM-Avance-Corp/app/src/components/gestion-diaria/registro-actividad.tsx
@@ -410,7 +410,7 @@ function RegistroDelAmbito({ dia, analistaIds, mostrarAnalista, permitirEquipo =
  * falta con el foco DENTRO, lo entrega al título «¿Qué hice hoy?» en vez de
  * dejarlo caer al inicio de la página.
  */
-function BotonVerMasCompacto({ ocupado, error, onPulsar, alSalirConFoco }: {
+export function BotonVerMasCompacto({ ocupado, error, onPulsar, alSalirConFoco }: {
   ocupado: boolean
   error: boolean
   onPulsar: () => void
diff --git a/CRM-Avance-Corp/app/src/components/gestion-diaria/resumen-analista.test.tsx b/CRM-Avance-Corp/app/src/components/gestion-diaria/resumen-analista.test.tsx
index 9cc47a71..16edb2be 100644
--- a/CRM-Avance-Corp/app/src/components/gestion-diaria/resumen-analista.test.tsx
+++ b/CRM-Avance-Corp/app/src/components/gestion-diaria/resumen-analista.test.tsx
@@ -82,3 +82,15 @@ describe('ResumenAnalista', () => {
     expect(within(screen.getByRole('list', { name: 'Otros motivos de atención' })).getByText('Tareas vencidas')).toBeInTheDocument()
   })
 })
+
+describe('G4b: «Citas agendadas» abre su lista', () => {
+  it('con abrirCitas, el cuadro lleva «Ver citas»; sin él, no ofrece un enlace muerto', () => {
+    const abrirCitas = vi.fn()
+    const { unmount } = render(<ResumenAnalista fila={conLlamadas} dia="2026-09-21" minimo={5} esHoy ahora={AHORA} abrirLlamadas={vi.fn()} abrirCitas={abrirCitas} />)
+    fireEvent.click(screen.getByRole('button', { name: 'Ver citas agendadas de KAREN DÍAZ' }))
+    expect(abrirCitas).toHaveBeenCalledOnce()
+    unmount()
+    montar(conLlamadas)
+    expect(screen.queryByRole('button', { name: /^Ver citas/ })).not.toBeInTheDocument()
+  })
+})
diff --git a/CRM-Avance-Corp/app/src/components/gestion-diaria/resumen-analista.tsx b/CRM-Avance-Corp/app/src/components/gestion-diaria/resumen-analista.tsx
index 9c483383..8b1043d8 100644
--- a/CRM-Avance-Corp/app/src/components/gestion-diaria/resumen-analista.tsx
+++ b/CRM-Avance-Corp/app/src/components/gestion-diaria/resumen-analista.tsx
@@ -33,7 +33,7 @@ const plural = (n: number, uno: string, varios: string) => `${n} ${n === 1 ? uno
 
 const FECHA_RESUMEN = new Intl.DateTimeFormat('es-PE', { day: 'numeric', month: 'long', year: 'numeric', timeZone: 'America/Lima' })
 
-export function ResumenAnalista({ fila: f, dia, minimo, esHoy, ahora, abrirLlamadas, abrirPendientes }: {
+export function ResumenAnalista({ fila: f, dia, minimo, esHoy, ahora, abrirLlamadas, abrirPendientes, abrirCitas }: {
   fila: FilaEquipoPresentada
   /** El día consultado (AAAA-MM-DD): se dice, también dentro de la ventana. */
   dia: string
@@ -44,6 +44,8 @@ export function ResumenAnalista({ fila: f, dia, minimo, esHoy, ahora, abrirLlama
   abrirLlamadas: () => void
   /** Sin él (gerencia, hasta tener permiso sobre pendientes) las vencidas se dicen sin enlace. */
   abrirPendientes?: ((soloVencidas: boolean) => void) | undefined
+  /** G4b: la lista exacta de las citas agendadas ese día. */
+  abrirCitas?: (() => void) | undefined
 }): JSX.Element {
   const atencion = presentarAtencion(f)
   const contacto = presentarContacto(f.marcador, minimo)
@@ -96,6 +98,9 @@ export function ResumenAnalista({ fila: f, dia, minimo, esHoy, ahora, abrirLlama
         <Cuadro etiqueta="Citas agendadas">
           <span className="block text-[28px] font-extrabold leading-tight tabular-nums text-primary">{f.marcador.citas_agendadas}</span>
           <span className="block text-xs text-[var(--muted-foreground-strong)]">desde «Agendó cita»</span>
+          {abrirCitas && <button type="button" onClick={abrirCitas} aria-label={`Ver citas agendadas de ${f.nombre_completo}`} className={ENLACE}>
+            Ver citas<ChevronRight aria-hidden className="size-3.5" />
+          </button>}
         </Cuadro>
         <Cuadro etiqueta="Pendientes">
           <span className="block text-[28px] font-extrabold leading-tight tabular-nums text-primary">{f.tareas_pendientes}</span>
diff --git a/CRM-Avance-Corp/app/src/components/gestion-diaria/tabla-equipos-gerencia.tsx b/CRM-Avance-Corp/app/src/components/gestion-diaria/tabla-equipos-gerencia.tsx
index ea8d69e7..b255c44a 100644
--- a/CRM-Avance-Corp/app/src/components/gestion-diaria/tabla-equipos-gerencia.tsx
+++ b/CRM-Avance-Corp/app/src/components/gestion-diaria/tabla-equipos-gerencia.tsx
@@ -167,8 +167,8 @@ function CifrasEquipo({ f, del, en, abrir, umbrales, sinDetalle, total = false }
   umbrales: v.InferOutput<typeof UmbralesSchema> | null; sinDetalle: 'cargando' | 'error'; total?: boolean
 }): JSX.Element {
   const ver = total
-    ? { llamadas: 'ver en el registro general', citas: 'ver los equipos ordenados por citas', vencidas: 'ver los equipos con vencidas', atencion: 'ver los equipos con atención' }
-    : { llamadas: 'ver en el registro', citas: 'ver por analista', vencidas: 'ver por analista', atencion: 'ver quiénes' }
+    ? { llamadas: 'ver en el registro general', citas: 'ver la lista', vencidas: 'ver los equipos con vencidas', atencion: 'ver los equipos con atención' }
+    : { llamadas: 'ver en el registro', citas: 'ver la lista', vencidas: 'ver por analista', atencion: 'ver quiénes' }
   return <>
     <td data-etiqueta="Llamadas" className="px-2 text-right text-sm tabular-nums text-foreground">
       {f.llamadas > 0 || total ? <button type="button" onClick={(e) => abrir('llamadas', e.currentTarget)} aria-label={`${plural(f.llamadas, 'llamada', 'llamadas')} ${del}: ${ver.llamadas}`}
diff --git a/CRM-Avance-Corp/app/src/data/gestion-diaria-citas-api.ts b/CRM-Avance-Corp/app/src/data/gestion-diaria-citas-api.ts
new file mode 100644
index 00000000..26b535e4
--- /dev/null
+++ b/CRM-Avance-Corp/app/src/data/gestion-diaria-citas-api.ts
@@ -0,0 +1,19 @@
+import { sb } from '@/lib/supabase'
+import { validarPaginaCitas, type PaginaCitas, type PedidoCitas } from '@/lib/gestion-diaria-citas'
+import { CrmApiError } from './crm-api'
+import { soloPresentes } from './argumentos-rpc'
+
+/** G4b: una página de la lista exacta de citas agendadas; el servidor decide el ámbito. */
+export async function listarCitasGestion(pedido: PedidoCitas, signal?: AbortSignal): Promise<PaginaCitas> {
+  if (!sb) throw new CrmApiError('No hay conexión con el CRM.', 'SIN_CLIENTE')
+  let consulta = sb.schema('crm').rpc('gestion_diaria_citas_fn', {
+    p_dia: pedido.dia, p_ambito: pedido.ambito, p_limite: pedido.limite,
+    ...soloPresentes({ p_id: pedido.id ?? undefined, p_despues_de: pedido.cursor?.despues_de, p_despues_id: pedido.cursor?.despues_id }),
+  })
+  if (signal) consulta = consulta.abortSignal(signal)
+  const { data, error } = await consulta
+  if (error) throw new CrmApiError(error.message, error.code)
+  const pagina = validarPaginaCitas(data, pedido)
+  if (!pagina) throw new CrmApiError('No se pudo confirmar la lista completa de citas.', 'GESTION_DIARIA_CITAS_CONTRACT')
+  return pagina
+}
diff --git a/CRM-Avance-Corp/app/src/data/gestion-diaria-citas-queries.test.tsx b/CRM-Avance-Corp/app/src/data/gestion-diaria-citas-queries.test.tsx
new file mode 100644
index 00000000..a604cc48
--- /dev/null
+++ b/CRM-Avance-Corp/app/src/data/gestion-diaria-citas-queries.test.tsx
@@ -0,0 +1,65 @@
+import type { ReactNode } from 'react'
+import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
+import { act, renderHook, waitFor } from '@testing-library/react'
+import { beforeEach, describe, expect, it, vi } from 'vitest'
+import type { PedidoCitas, PaginaCitas } from '@/lib/gestion-diaria-citas'
+import type { Yo } from '@/lib/tipos'
+import { CrmApiError } from './crm-api'
+
+const dobles = vi.hoisted(() => ({ listar: vi.fn(), yo: null as Yo | null }))
+vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: dobles.yo }) }))
+vi.mock('@/lib/store-context', () => ({ useCRMData: () => ({ tareas: [], equipo: [], ambito: { leads: [] } }) }))
+vi.mock('@/lib/ahora', () => ({ useAhora: () => Date.parse('2026-09-24T17:00:00Z') }))
+vi.mock('./gestion-diaria-citas-api', () => ({ listarCitasGestion: dobles.listar }))
+const { useCitasGestion } = await import('./gestion-diaria-citas-queries')
+
+const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`
+const vacia = (p: PedidoCitas): PaginaCitas => ({ version: 1, zona: 'America/Lima', dia: p.dia, ambito: p.ambito, id: p.id,
+  generado_en: '2026-09-24T17:00:00.000Z', limite: p.limite, resumen: { total: 0 }, items: [], hay_mas: false, siguiente_cursor: null })
+let cliente: QueryClient
+const envolver = ({ children }: { children: ReactNode }) => <QueryClientProvider client={cliente}>{children}</QueryClientProvider>
+beforeEach(() => {
+  vi.clearAllMocks(); cliente = new QueryClient({ defaultOptions: { queries: { retry: false } } })
+  dobles.listar.mockImplementation(async (p: PedidoCitas) => vacia(p))
+})
+
+describe('G4b: quién pide la lista de citas', () => {
+  it('gerencia pide cualquier ámbito y el pedido lleva el día, el ámbito y el id', async () => {
+    dobles.yo = { id: id(1), rol: 'gerencia', demo: false } as Yo
+    const { result } = renderHook(() => useCitasGestion('2026-09-24', 'equipo', id(2), true), { wrapper: envolver })
+    await waitFor(() => expect(result.current.total).toBe(0))
+    expect(dobles.listar).toHaveBeenCalledWith(expect.objectContaining({ dia: '2026-09-24', ambito: 'equipo', id: id(2), cursor: null }), expect.any(AbortSignal))
+  })
+  it('supervisión sólo pide el ámbito «analista»', async () => {
+    dobles.yo = { id: id(3), rol: 'supervisor', demo: false } as Yo
+    const analista = renderHook(() => useCitasGestion('2026-09-24', 'analista', id(4), true), { wrapper: envolver })
+    await waitFor(() => expect(dobles.listar).toHaveBeenCalledTimes(1))
+    renderHook(() => useCitasGestion('2026-09-24', 'operacion', null, true), { wrapper: envolver })
+    await act(async () => { await Promise.resolve() })
+    expect(dobles.listar).toHaveBeenCalledTimes(1)
+    expect(analista.result.current.sinPermiso).toBe(false)
+  })
+  it.each(['vendedor', 'coordinador', 'directorio'] as const)('%s no pide la lista', async (rol) => {
+    dobles.yo = { id: id(5), rol, demo: false } as Yo
+    const { result } = renderHook(() => useCitasGestion('2026-09-24', 'analista', id(4), true), { wrapper: envolver })
+    await act(async () => { await Promise.resolve() })
+    expect(dobles.listar).not.toHaveBeenCalled()
+    expect(result.current.items).toEqual([])
+  })
+  it('no consulta hasta hacerse visible', async () => {
+    dobles.yo = { id: id(1), rol: 'gerencia', demo: false } as Yo
+    const { rerender } = renderHook(({ visible }) => useCitasGestion('2026-09-24', 'operacion', null, visible), { wrapper: envolver, initialProps: { visible: false } })
+    await act(async () => { await Promise.resolve() })
+    expect(dobles.listar).not.toHaveBeenCalled()
+    rerender({ visible: true })
+    await waitFor(() => expect(dobles.listar).toHaveBeenCalledTimes(1))
+  })
+  it('un 42501 retira las filas y no vuelve a consultar solo', async () => {
+    dobles.yo = { id: id(1), rol: 'gerencia', demo: false } as Yo
+    dobles.listar.mockRejectedValue(new CrmApiError('revocado', '42501'))
+    const { result } = renderHook(() => useCitasGestion('2026-09-24', 'operacion', null, true), { wrapper: envolver })
+    await waitFor(() => expect(result.current.sinPermiso).toBe(true))
+    expect(result.current.items).toEqual([])
+    expect(dobles.listar).toHaveBeenCalledTimes(1)
+  })
+})
diff --git a/CRM-Avance-Corp/app/src/data/gestion-diaria-citas-queries.ts b/CRM-Avance-Corp/app/src/data/gestion-diaria-citas-queries.ts
new file mode 100644
index 00000000..07344453
--- /dev/null
+++ b/CRM-Avance-Corp/app/src/data/gestion-diaria-citas-queries.ts
@@ -0,0 +1,79 @@
+import { useEffect, useMemo, useRef } from 'react'
+import { useInfiniteQuery, useQueryClient } from '@tanstack/react-query'
+import { useAuth } from '@/lib/auth-context'
+import { useCRMData } from '@/lib/store-context'
+import { useAhora } from '@/lib/ahora'
+import { analistasDelEquipo } from '@/lib/gestion-diaria'
+import { citasDesdeDemo, unirPaginasCitas, type AmbitoCitas, type CursorCitas } from '@/lib/gestion-diaria-citas'
+import { CrmApiError } from './crm-api'
+import { gestionDiariaKeys } from './gestion-diaria-queries'
+import { listarCitasGestion } from './gestion-diaria-citas-api'
+
+export const LIMITE_CITAS = 25
+export const claveCitas = (actor: string | null, rol: string | null, demo: boolean | null, dia: string, ambito: AmbitoCitas, id: string | null) =>
+  [...gestionDiariaKeys.raiz(), actor, rol, demo, 'citas-agendadas', dia, ambito, id, LIMITE_CITAS] as const
+
+/**
+ * G4b: la lista exacta de citas agendadas de un ámbito. Se consulta al abrirla (una foto:
+ * sin refresco periódico, como el registro que se abre) y «Actualizar» vuelve a pedirla.
+ * Supervisión sólo pide el ámbito «analista»; Gerencia, cualquiera. El servidor decide.
+ */
+export function useCitasGestion(dia: string, ambito: AmbitoCitas, id: string | null, visible: boolean, actualizacion = 0) {
+  const { yo } = useAuth()
+  const { tareas, equipo, ambito: alcance } = useCRMData()
+  const ahora = useAhora()
+  const cliente = useQueryClient()
+  const revocada = useRef(false)
+  const autorizado = yo?.rol === 'gerencia' || (yo?.rol === 'supervisor' && ambito === 'analista')
+  const clave = useMemo(() => [...claveCitas(yo?.id ?? null, yo?.rol ?? null, yo?.demo ?? null, dia, ambito, id), actualizacion],
+    [yo?.id, yo?.rol, yo?.demo, dia, ambito, id, actualizacion])
+  const ambitoClave = useMemo(() => clave.slice(0, -2), [clave])
+  const identidad = JSON.stringify(ambitoClave)
+  const ultimaIdentidad = useRef(identidad)
+  if (ultimaIdentidad.current !== identidad) {
+    ultimaIdentidad.current = identidad
+    revocada.current = false
+  }
+  const consulta = useInfiniteQuery({
+    queryKey: clave,
+    initialPageParam: null as CursorCitas | null,
+    queryFn: ({ pageParam, signal }) => {
+      if (!yo || !autorizado) throw new CrmApiError('Consulta no autorizada.', '42501')
+      const pedido = { dia, ambito, id, limite: LIMITE_CITAS, cursor: pageParam }
+      if (yo.demo) {
+        // En demo, el mismo ámbito que el servidor: Supervisión su árbol; Gerencia todo.
+        if (yo.rol === 'supervisor' && (id === null || !analistasDelEquipo(equipo, yo.id).includes(id))) throw new CrmApiError('Consulta no autorizada.', '42501')
+        return Promise.resolve(citasDesdeDemo(pedido, { miembros: equipo, leads: alcance.leads, tareas, ahora }))
+      }
+      return listarCitasGestion(pedido, signal)
+    },
+    getNextPageParam: (ultima) => ultima.siguiente_cursor,
+    enabled: autorizado && visible && !revocada.current,
+    refetchOnWindowFocus: false, refetchOnReconnect: false,
+    staleTime: Infinity, gcTime: 0, retry: false,
+  })
+  const denegada = consulta.error instanceof CrmApiError && consulta.error.code === '42501'
+  const sinPermiso = denegada || revocada.current
+  useEffect(() => {
+    if (!denegada) return
+    // Bloquear primero: limpiar la caché no debe provocar otra consulta automática.
+    revocada.current = true
+    void cliente.cancelQueries({ queryKey: ambitoClave })
+    cliente.setQueriesData({ queryKey: ambitoClave }, { pages: [], pageParams: [] })
+  }, [denegada, cliente, ambitoClave])
+  const paginas = autorizado && !sinPermiso ? consulta.data?.pages ?? [] : []
+  return {
+    items: unirPaginasCitas(paginas), total: paginas[0]?.resumen.total ?? null,
+    consultadoEn: paginas[0]?.generado_en ?? null,
+    cargando: autorizado && !sinPermiso && consulta.isPending,
+    enVuelo: consulta.isFetching, error: sinPermiso ? new CrmApiError('Ya no tienes acceso a estas citas.', '42501') : consulta.error,
+    sinPermiso, hayMas: !sinPermiso && !consulta.error && consulta.hasNextPage,
+    cargarMas: async () => { if (autorizado && !sinPermiso && !consulta.isFetching && consulta.hasNextPage) await consulta.fetchNextPage() },
+    recargar: async () => {
+      if (!autorizado) return
+      revocada.current = false
+      await cliente.cancelQueries({ queryKey: clave, exact: true })
+      await cliente.resetQueries({ queryKey: clave, exact: true })
+    },
+  }
+}
diff --git a/CRM-Avance-Corp/app/src/lib/gestion-diaria-citas.test.ts b/CRM-Avance-Corp/app/src/lib/gestion-diaria-citas.test.ts
new file mode 100644
index 00000000..1a243add
--- /dev/null
+++ b/CRM-Avance-Corp/app/src/lib/gestion-diaria-citas.test.ts
@@ -0,0 +1,113 @@
+// G4b: la lista exacta de «Citas agendadas». La frontera rechaza cualquier página que no
+// se pueda confirmar entera, y en demo la lista cuadra con la cifra del pulso y del detalle.
+import { describe, expect, it, vi } from 'vitest'
+import * as v from 'valibot'
+import { PulsoGerenciaSchema } from './gestion-diaria-pulso'
+import { detalleOperacionDesdeDemo, pulsoGerenciaDesdeDemo, type MundoDemo } from './gestion-diaria-pulso-demo'
+import { citasDesdeDemo, unirPaginasCitas, validarPaginaCitas, type CitaAgendada, type PaginaCitas, type PedidoCitas } from './gestion-diaria-citas'
+import type { Tarea } from './tipos'
+
+const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`
+const cita = (n: number, creado: string, extra: Partial<CitaAgendada> = {}): CitaAgendada => ({
+  id: id(n), vendedor_id: id(90), vendedor_nombre: 'ANALISTA', lead_id: id(200 + n), lead_nombre: `LEAD ${n}`,
+  vence_en: '2026-09-26T15:00:00.000Z', estado: 'pendiente', creado_en: creado, ...extra,
+})
+const pedido: PedidoCitas = { dia: '2026-09-24', ambito: 'analista', id: id(90), limite: 2, cursor: null }
+const pagina = (items: CitaAgendada[], extra: Partial<PaginaCitas> = {}): PaginaCitas => ({
+  version: 1, zona: 'America/Lima', dia: '2026-09-24', ambito: 'analista', id: id(90), generado_en: '2026-09-24T17:00:00.000Z',
+  limite: 2, resumen: { total: items.length }, items, hay_mas: false, siguiente_cursor: null, ...extra,
+})
+
+describe('validarPaginaCitas', () => {
+  const a = cita(1, '2026-09-24T05:00:00.000Z') // primer instante del día Lima
+  const b = cita(2, '2026-09-25T04:59:59.999999Z') // último
+  it('acepta una página completa, en orden y dentro del día Lima', () => {
+    expect(validarPaginaCitas(pagina([a, b]), pedido)).not.toBeNull()
+  })
+  it.each([
+    ['otro día', pagina([a, b], { dia: '2026-09-23' })],
+    ['otro ámbito', pagina([a, b], { ambito: 'equipo' })],
+    ['otro id', pagina([a, b], { id: id(91) })],
+    ['otro límite', pagina([a, b], { limite: 3 })],
+    ['clave desconocida', { ...pagina([a, b]), extra: 1 }],
+    ['fuera del día (antes)', pagina([cita(3, '2026-09-24T04:59:59.999Z'), b])],
+    ['fuera del día (después)', pagina([a, cita(4, '2026-09-25T05:00:00.000Z')])],
+    ['desordenada', pagina([b, a])],
+    ['repetida', pagina([a, a], { resumen: { total: 2 } })],
+    ['de otro analista en su ámbito', pagina([a, cita(5, '2026-09-24T06:00:00.000Z', { vendedor_id: id(91) })])],
+    ['lead sin nombre', pagina([cita(6, '2026-09-24T06:00:00.000Z', { lead_nombre: null })])],
+    ['total que no cuadra sin más páginas', pagina([a, b], { resumen: { total: 3 } })],
+    ['hay_mas sin cursor', pagina([a, b], { hay_mas: true, resumen: { total: 3 } })],
+    ['cursor que no es la última fila', pagina([a, b], { hay_mas: true, resumen: { total: 3 }, siguiente_cursor: { despues_de: a.creado_en, despues_id: a.id } })],
+    ['estado desconocido', pagina([{ ...a, estado: 'borrada' as never }])],
+  ])('rechaza: %s', (_, valor) => {
+    expect(validarPaginaCitas(valor, pedido)).toBeNull()
+  })
+  it('una segunda página debe seguir al cursor pedido', () => {
+    const primera = pagina([a, b], { hay_mas: true, resumen: { total: 3 }, siguiente_cursor: { despues_de: b.creado_en, despues_id: b.id } })
+    expect(validarPaginaCitas(primera, pedido)).not.toBeNull()
+    const c = cita(7, '2026-09-24T06:00:00.000Z')
+    const conCursor = { ...pedido, cursor: { despues_de: b.creado_en, despues_id: b.id } }
+    // Anterior al cursor: no es la continuación.
+    expect(validarPaginaCitas(pagina([c], { resumen: { total: 3 } }), conCursor)).toBeNull()
+    expect(unirPaginasCitas([primera]).map((x) => x.id)).toEqual([a.id, b.id])
+  })
+  it('en «operación» y «fuera» las filas son de cualquier autor, también sin autor', () => {
+    const libre = { ...pedido, ambito: 'fuera' as const, id: null }
+    expect(validarPaginaCitas(pagina([cita(8, '2026-09-24T06:00:00.000Z', { vendedor_id: null, vendedor_nombre: null })], { ambito: 'fuera', id: null }), libre)).not.toBeNull()
+  })
+})
+
+// El mundo demo se siembra RELATIVO al reloj: se fija antes de importarlo.
+const AHORA = Date.parse('2026-09-24T17:00:00Z')
+vi.useFakeTimers()
+vi.setSystemTime(AHORA)
+const demo = await import('./demo')
+vi.useRealTimers()
+const HOY = '2026-09-24'
+const reunion = (n: number, lead_id: string | null, vendedor_id: string | null, creado_en: string): Tarea => ({
+  id: id(500 + n), lead_id, perfil_id: lead_id ? null : 'd-ger', vendedor_id, tipo: 'reunion', titulo: `Cita ${n}`,
+  vence_en: '2026-09-26T15:00:00.000Z', estado: 'pendiente', reprogramaciones: 0, activo: true, creado_en,
+})
+
+describe('citas en demo: la lista ES la cifra', () => {
+  const lead = (vendedor: string) => demo.LEADS_DEMO.find((l) => l.activo && l.vendedor_id === vendedor)!
+  const sinDueno = demo.LEADS_DEMO.find((l) => !l.vendedor_id)
+  const extra: Tarea[] = [
+    reunion(1, lead('d-v1').id, 'd-v1', '2026-09-24T05:00:00.000Z'),
+    reunion(2, lead('d-v1').id, 'd-v1', '2026-09-24T14:00:00.000Z'),
+    reunion(3, lead('d-v3').id, 'd-v3', '2026-09-24T15:00:00.000Z'),
+    reunion(4, null, null, '2026-09-24T16:00:00.000Z'),
+    reunion(5, lead('d-v1').id, 'd-v1', '2026-09-23T12:00:00.000Z'),
+    ...(sinDueno ? [reunion(6, sinDueno.id, null, '2026-09-24T16:30:00.000Z')] : []),
+  ]
+  const mundo: MundoDemo = { miembros: demo.EQUIPO_DEMO, leads: demo.LEADS_DEMO, actividades: demo.ACTIVIDADES_DEMO, tareas: [...demo.TAREAS_DEMO, ...extra], ahora: AHORA }
+  const pulso = v.parse(PulsoGerenciaSchema, pulsoGerenciaDesdeDemo(mundo, HOY))
+  const lista = (ambito: PedidoCitas['ambito'], clave: string | null) => citasDesdeDemo({ dia: HOY, ambito, id: clave, limite: 100, cursor: null }, mundo)
+  it('cada equipo y «fuera» son su cifra del pulso, y juntos son la operación sin solaparse', () => {
+    const porEquipo = pulso.equipos.map((e) => ({ e, p: lista(e.clave === 'fuera' ? 'fuera' : 'equipo', e.clave === 'fuera' ? null : e.clave) }))
+    for (const { e, p } of porEquipo) expect(p.resumen.total).toBe(e.metricas.citas_agendadas)
+    const operacion = lista('operacion', null)
+    expect(operacion.resumen.total).toBe(pulso.actual.citas_agendadas)
+    expect(operacion.resumen.total).toBeGreaterThan(0)
+    const union = porEquipo.flatMap(({ p }) => p.items.map((x) => x.id))
+    expect(new Set(union).size).toBe(union.length)
+    expect(union.toSorted()).toEqual(operacion.items.map((x) => x.id).toSorted())
+  })
+  it('cada analista es su cifra del detalle; el día anterior no entra', () => {
+    const detalle = detalleOperacionDesdeDemo(mundo, HOY)
+    for (const f of detalle.equipo) expect(lista('analista', f.analista_id).resumen.total).toBe(f.marcador.citas_agendadas)
+    expect(lista('analista', 'd-v1').items.map((x) => x.id)).toEqual([id(501), id(502)])
+    expect(lista('fuera', null).items.map((x) => x.id)).toContain(id(504))
+  })
+  it('pagina con cursor sin repetir ni saltar', () => {
+    const primera = citasDesdeDemo({ dia: HOY, ambito: 'operacion', id: null, limite: 2, cursor: null }, mundo)
+    expect(primera.hay_mas).toBe(primera.resumen.total > 2)
+    if (primera.siguiente_cursor) {
+      const segunda = citasDesdeDemo({ dia: HOY, ambito: 'operacion', id: null, limite: 2, cursor: primera.siguiente_cursor }, mundo)
+      expect(segunda.items.some((x) => primera.items.some((y) => y.id === x.id))).toBe(false)
+      // Los ids demo no son UUID (el demo no pasa por la frontera): se comprueba la semántica del cursor.
+      expect([...primera.items, ...segunda.items].length).toBe(Math.min(4, primera.resumen.total))
+    }
+  })
+})
diff --git a/CRM-Avance-Corp/app/src/lib/gestion-diaria-citas.ts b/CRM-Avance-Corp/app/src/lib/gestion-diaria-citas.ts
new file mode 100644
index 00000000..51f8cec0
--- /dev/null
+++ b/CRM-Avance-Corp/app/src/lib/gestion-diaria-citas.ts
@@ -0,0 +1,108 @@
+// G4b (27/09/2026): la lista EXACTA de «Citas agendadas» de Gestión Diaria —tareas
+// `reunion` CREADAS en el día Lima—, la misma definición que la cifra. La frontera es
+// estricta: forma cerrada y coherencia de cada página (día, ámbito, orden, cursor,
+// total). Nunca se descarta una fila para aparentar una lista completa.
+import * as v from 'valibot'
+import { instantePendiente } from './gestion-diaria-pendientes'
+import { citasDelDiaDemo, type MundoDemo } from './gestion-diaria-pulso-demo'
+
+export type AmbitoCitas = 'analista' | 'equipo' | 'fuera' | 'operacion'
+// El CHECK vivo de crm.tareas (tareas_estado_valido) admite también «reprogramada».
+export const ESTADOS_CITA = ['pendiente', 'completada', 'cancelada', 'no_show', 'reprogramada'] as const
+export type EstadoCita = (typeof ESTADOS_CITA)[number]
+
+const Uuid = v.pipe(v.string(), v.uuid())
+const Instante = v.pipe(v.string(), v.check((s) => instantePendiente(s) !== null))
+const Dia = v.pipe(v.string(), v.regex(/^\d{4}-\d{2}-\d{2}$/))
+const Natural = v.pipe(v.number(), v.check((n) => Number.isSafeInteger(n) && n >= 0))
+const Nombre = v.nullable(v.pipe(v.string(), v.check((s) => s.trim().length > 0)))
+
+export const CursorCitasSchema = v.strictObject({ despues_de: Instante, despues_id: Uuid })
+export type CursorCitas = v.InferOutput<typeof CursorCitasSchema>
+export const CitaAgendadaSchema = v.strictObject({
+  id: Uuid, vendedor_id: v.nullable(Uuid), vendedor_nombre: Nombre,
+  lead_id: v.nullable(Uuid), lead_nombre: Nombre,
+  vence_en: Instante, estado: v.picklist(ESTADOS_CITA), creado_en: Instante,
+})
+export type CitaAgendada = v.InferOutput<typeof CitaAgendadaSchema>
+export const PaginaCitasSchema = v.strictObject({
+  version: v.literal(1), zona: v.literal('America/Lima'), dia: Dia,
+  ambito: v.picklist(['analista', 'equipo', 'fuera', 'operacion']), id: v.nullable(Uuid),
+  generado_en: Instante, limite: v.pipe(Natural, v.minValue(1), v.maxValue(100)),
+  resumen: v.strictObject({ total: Natural }),
+  items: v.array(CitaAgendadaSchema), hay_mas: v.boolean(), siguiente_cursor: v.nullable(CursorCitasSchema),
+})
+export type PaginaCitas = v.InferOutput<typeof PaginaCitasSchema>
+export interface PedidoCitas { dia: string; ambito: AmbitoCitas; id: string | null; limite: number; cursor: CursorCitas | null }
+
+/** Orden del servidor: (creado_en, id), con microsegundos. */
+export function compararCitas(a: Pick<CitaAgendada, 'creado_en' | 'id'>, b: Pick<CitaAgendada, 'creado_en' | 'id'>): number {
+  const x = instantePendiente(a.creado_en), y = instantePendiente(b.creado_en)
+  if (x === null || y === null) throw new Error('Fecha de cita inválida')
+  const idA = a.id.toLowerCase(), idB = b.id.toLowerCase()
+  return x < y ? -1 : x > y ? 1 : idA < idB ? -1 : idA > idB ? 1 : 0
+}
+
+/** [inicio, fin) del día Lima en microsegundos (Lima no cambia de hora: UTC−5). */
+function ventanaDia(dia: string): [bigint, bigint] | null {
+  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(dia)
+  if (!m) return null
+  const inicio = Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3]), 5)
+  const fecha = new Date(inicio)
+  if (fecha.getUTCFullYear() !== Number(m[1]) || fecha.getUTCMonth() + 1 !== Number(m[2]) || fecha.getUTCDate() !== Number(m[3])) return null
+  return [BigInt(inicio) * 1000n, BigInt(inicio + 86_400_000) * 1000n]
+}
+
+const mismoId = (a: string | null, b: string | null) => (a === null || b === null) ? a === b : a.toLowerCase() === b.toLowerCase()
+
+export function validarPaginaCitas(valor: unknown, pedido: PedidoCitas): PaginaCitas | null {
+  if (pedido.cursor && !v.safeParse(CursorCitasSchema, pedido.cursor).success) return null
+  const parsed = v.safeParse(PaginaCitasSchema, valor)
+  const ventana = ventanaDia(pedido.dia)
+  if (!parsed.success || !ventana) return null
+  const p = parsed.output
+  if (p.dia !== pedido.dia || p.ambito !== pedido.ambito || !mismoId(p.id, pedido.id) || p.limite !== pedido.limite
+    || p.items.length > p.limite || p.items.length > p.resumen.total
+    || p.hay_mas !== (p.siguiente_cursor !== null)
+    || (p.hay_mas && (p.items.length !== p.limite || p.resumen.total <= p.items.length))
+    || (!pedido.cursor && !p.hay_mas && p.items.length !== p.resumen.total)) return null
+  const ids = new Set<string>()
+  let anterior = pedido.cursor ? { creado_en: pedido.cursor.despues_de, id: pedido.cursor.despues_id } : null
+  for (const item of p.items) {
+    const creada = instantePendiente(item.creado_en)!
+    if (ids.has(item.id.toLowerCase()) || creada < ventana[0] || creada >= ventana[1]
+      || (anterior && compararCitas(item, anterior) <= 0)
+      || (p.ambito === 'analista' && !mismoId(item.vendedor_id, pedido.id))
+      || ((item.lead_id === null) !== (item.lead_nombre === null))) return null
+    ids.add(item.id.toLowerCase()); anterior = item
+  }
+  const ultima = p.items.at(-1)
+  if (p.siguiente_cursor && (!ultima || compararCitas(ultima, { creado_en: p.siguiente_cursor.despues_de, id: p.siguiente_cursor.despues_id }) !== 0)) return null
+  return p
+}
+
+/** Las páginas se suman en orden; un id repetido conserva su última foto. */
+export function unirPaginasCitas(paginas: readonly PaginaCitas[]): CitaAgendada[] {
+  const porId = new Map<string, CitaAgendada>()
+  for (const pagina of paginas) for (const item of pagina.items) porId.set(item.id.toLowerCase(), item)
+  return [...porId.values()].sort(compararCitas)
+}
+
+/** Sólo demo: la misma forma que el servidor, con la atribución del pulso demo. */
+export function citasDesdeDemo(pedido: PedidoCitas, mundo: Pick<MundoDemo, 'miembros' | 'leads' | 'tareas' | 'ahora'>): PaginaCitas {
+  const leads = new Map(mundo.leads.map((l) => [l.id, l]))
+  const nombres = new Map(mundo.miembros.map((m) => [m.perfil_id, m.nombre_completo]))
+  const todas: CitaAgendada[] = citasDelDiaDemo(mundo, pedido.dia, pedido.ambito, pedido.id).map((t) => {
+    const lead = t.lead_id ? leads.get(t.lead_id) : undefined
+    const nombre = lead?.nombre_completo.trim() || null
+    const dueno = (lead ? lead.vendedor_id : t.vendedor_id) ?? null
+    return { id: t.id, vendedor_id: dueno, vendedor_nombre: dueno ? nombres.get(dueno)?.trim() || null : null,
+      lead_id: nombre ? lead!.id : null, lead_nombre: nombre, vence_en: t.vence_en,
+      estado: (ESTADOS_CITA as readonly string[]).includes(t.estado) ? t.estado as EstadoCita : 'pendiente', creado_en: t.creado_en }
+  }).sort(compararCitas)
+  const seleccion = todas.filter((c) => !pedido.cursor || compararCitas(c, { creado_en: pedido.cursor.despues_de, id: pedido.cursor.despues_id }) > 0)
+  const pagina = seleccion.slice(0, pedido.limite), ultima = pagina.at(-1), hayMas = seleccion.length > pedido.limite
+  return { version: 1, zona: 'America/Lima', dia: pedido.dia, ambito: pedido.ambito, id: pedido.id,
+    generado_en: new Date(mundo.ahora).toISOString(), limite: pedido.limite, resumen: { total: todas.length }, items: pagina,
+    hay_mas: hayMas, siguiente_cursor: hayMas && ultima ? { despues_de: ultima.creado_en, despues_id: ultima.id } : null }
+}
diff --git a/CRM-Avance-Corp/app/src/lib/gestion-diaria-pulso-demo.ts b/CRM-Avance-Corp/app/src/lib/gestion-diaria-pulso-demo.ts
index f6a07c33..2512e041 100644
--- a/CRM-Avance-Corp/app/src/lib/gestion-diaria-pulso-demo.ts
+++ b/CRM-Avance-Corp/app/src/lib/gestion-diaria-pulso-demo.ts
@@ -80,6 +80,34 @@ function organigrama(miembros: readonly Miembro[]): Organigrama {
   return { grupos: [...supervisores.values(), FUERA], equipoDe, porId, porNombre: new Map(miembros.map((m) => [m.nombre_completo, m])) }
 }
 
+export type AmbitoCitasDemo = 'analista' | 'equipo' | 'fuera' | 'operacion'
+
+/**
+ * G4b: las citas del día (tareas `reunion` CREADAS ese día) de un ámbito, con la MISMA
+ * atribución con la que el detalle y el pulso demo las cuentan: el dueño actual del lead
+ * para los analistas del organigrama; «fuera» para los analistas sin supervisor y para las
+ * que no son de nadie del organigrama. Así la lista cuadra con su cifra por construcción.
+ */
+export function citasDelDiaDemo(m: Pick<MundoDemo, 'miembros' | 'leads' | 'tareas'>, dia: string, ambito: AmbitoCitasDemo, id: string | null): Tarea[] {
+  const org = organigrama(m.miembros)
+  const leads = new Map(m.leads.map((l) => [l.id, l]))
+  return m.tareas.filter((t) => {
+    if (t.tipo !== 'reunion' || diaDe(t.creado_en) !== dia) return false
+    const lead = t.lead_id ? leads.get(t.lead_id) : undefined
+    // En el detalle cuenta la del lead de un analista del organigrama activo.
+    const analista = lead?.vendedor_id && org.equipoDe.has(lead.vendedor_id) ? lead.vendedor_id : null
+    const dueno = (lead ? lead.vendedor_id : t.vendedor_id) ?? null
+    // Sin lead y de un analista del organigrama no entra en ninguna cifra demo: tampoco aquí.
+    const clave = analista !== null ? org.equipoDe.get(analista)!.clave
+      : dueno === null || !org.equipoDe.has(dueno) ? FUERA.clave : null
+    if (clave === null) return false
+    if (ambito === 'operacion') return true
+    if (ambito === 'fuera') return clave === FUERA.clave
+    if (ambito === 'equipo') return clave === id
+    return analista === id
+  })
+}
+
 function contacto(filas: readonly Contacto[]) {
   const suma = (campo: keyof Contacto) => filas.reduce((n, f) => n + f[campo], 0)
   return { llamadas: suma('llamadas'), utiles: suma('utiles'), contestadas: suma('contestadas'), tasa_contacto: tasa(suma('contestadas'), suma('utiles')) }
diff --git a/CRM-Avance-Corp/app/src/screens/gestion-diaria/gerencia.test.tsx b/CRM-Avance-Corp/app/src/screens/gestion-diaria/gerencia.test.tsx
index d09d4a28..886fe5c1 100644
--- a/CRM-Avance-Corp/app/src/screens/gestion-diaria/gerencia.test.tsx
+++ b/CRM-Avance-Corp/app/src/screens/gestion-diaria/gerencia.test.tsx
@@ -19,6 +19,7 @@ vi.mock('@/data/gestion-diaria-pulso-queries', () => ({
   useHabitosGerencia: (_dia: string, dias: number) => { periodos.push(dias); return habitos }, useDetallePulso: () => detalle,
 }))
 vi.mock('@/components/gestion-diaria/ultimas-gestiones-supervisor', () => ({ UltimasGestionesSupervisor: () => null }))
+vi.mock('@/components/gestion-diaria/citas-agendadas', () => ({ CitasAgendadas: (p: { dia: string; ambito: string; id: string | null }) => <div data-testid="citas">{p.dia}:{p.ambito}:{String(p.id)}</div> }))
 vi.mock('@/components/gestion-diaria/registro-actividad', () => ({ RegistroActividad: (p: { dia: string; analistaIds: string[] | null; pestanaInicial?: string; onSinPermiso?: () => void }) => <div data-testid="registro">{p.dia}:{JSON.stringify(p.analistaIds)}:{p.pestanaInicial}<button onClick={p.onSinPermiso}>Simular denegación del registro</button></div> }))
 const { GestionDiariaGerencia } = await import('./gerencia')
 beforeEach(() => {
@@ -63,8 +64,8 @@ describe('Gerencia con el diseño de Gestión Diaria (27/09) sobre los contratos
     // Todo número se abre, también los ceros del total (Codex, 27/09).
     fireEvent.click(within(total).getByRole('button', { name: '0 llamadas de toda la operación: ver en el registro general' }))
     expect(screen.getByTestId('registro')).toHaveTextContent(':null:llamadas')
-    fireEvent.click(within(filaTotal()).getByRole('button', { name: '0 citas agendadas de toda la operación: ver los equipos ordenados por citas' }))
-    expect(screen.getByRole('button', { name: 'Ordenar equipos por citas' }).closest('th')).toHaveAttribute('aria-sort', 'descending')
+    fireEvent.click(within(filaTotal()).getByRole('button', { name: '0 citas agendadas de toda la operación: ver la lista' }))
+    expect(within(screen.getByRole('region', { name: 'Citas agendadas' })).getByTestId('citas')).toHaveTextContent(':operacion:null')
     expect(within(total).getByRole('button', { name: /^1008 tareas vencidas/ })).toBeInTheDocument()
     fireEvent.click(screen.getByRole('button', { name: 'Comparar días' }))
     expect(screen.getByRole('table', { name: 'Cifras del día, anterior y referencia' })).toHaveTextContent('Tasa de contacto——0 %')
@@ -237,8 +238,10 @@ describe('Gerencia con el diseño de Gestión Diaria (27/09) sobre los contratos
     fireEvent.click(within(filaTotal()).getByRole('button', { name: '2 sin registro en toda la operación: ver quiénes' }))
     const lista = screen.getByRole('list', { name: 'Analistas sin registro' })
     expect(within(lista).getAllByRole('button').map((b) => b.textContent)).toEqual([expect.stringContaining('ANALISTA ANIDADO'), expect.stringContaining('ANALISTA CUATRO')])
+    // G4b: las citas agendadas abren su lista exacta en la ficha.
     fireEvent.click(within(filaTotal()).getByRole('button', { name: /^3 citas agendadas de toda la operación/ }))
-    expect(screen.getByRole('button', { name: 'Ordenar equipos por citas' }).closest('th')).toHaveAttribute('aria-sort', 'descending')
+    expect(within(screen.getByRole('region', { name: 'Citas agendadas' })).getByTestId('citas')).toHaveTextContent(':operacion:null')
+    expect(screen.getByRole('heading', { level: 3, name: 'Citas agendadas: Toda la operación' })).toHaveFocus()
     fireEvent.click(within(filaTotal()).getByRole('button', { name: /^1008 tareas vencidas en toda la operación/ }))
     expect(screen.getByRole('button', { name: /^Con vencidas/ })).toHaveAttribute('aria-pressed', 'true')
     expect(screen.getByRole('button', { name: 'Ordenar equipos por vencidas' }).closest('th')).toHaveAttribute('aria-sort', 'descending')
@@ -319,8 +322,20 @@ describe('Gerencia con el diseño de Gestión Diaria (27/09) sobre los contratos
     fireEvent.change(screen.getByRole('searchbox', { name: 'Buscar equipo' }), { target: { value: 'ANIDADO' } })
     fireEvent.click(screen.getByRole('button', { name: /^Con atención/ }))
     expect(screen.getByRole('searchbox', { name: 'Buscar equipo' })).toHaveValue('')
-    fireEvent.click(screen.getByRole('button', { name: '1 cita agendada del Equipo de SUPERVISOR DOS: ver por analista' }))
-    expect(within(screen.getByRole('region', { name: 'Equipo de SUPERVISOR DOS' })).getByRole('button', { name: 'Ordenar por citas' }).closest('th')).toHaveAttribute('aria-sort', 'descending')
+    fireEvent.click(screen.getByRole('button', { name: '1 cita agendada del Equipo de SUPERVISOR DOS: ver la lista' }))
+    expect(within(screen.getByRole('region', { name: 'Citas agendadas' })).getByTestId('citas')).toHaveTextContent(`:equipo:${dos.clave}`)
+  })
+  it('G4b: la ficha del equipo abre sus citas y «fuera» pide su propio ámbito, nunca toda la operación', () => {
+    render(<GestionDiariaGerencia />)
+    const dos = pulso.datos!.equipos.find((e) => e.nombre === 'SUPERVISOR DOS')!
+    const ficha = screen.getByRole('region', { name: 'Detalle del Equipo de SUPERVISOR DOS' })
+    fireEvent.click(within(ficha).getByRole('button', { name: 'Ver citas agendadas del Equipo de SUPERVISOR DOS' }))
+    expect(screen.getByTestId('citas')).toHaveTextContent(`:equipo:${dos.clave}`)
+    fireEvent.click(screen.getByRole('button', { name: 'Seleccionar Fuera de equipos comerciales' }))
+    fireEvent.click(within(screen.getByRole('region', { name: 'Detalle del grupo Fuera de equipos comerciales' }))
+      .getByRole('button', { name: 'Ver citas agendadas del grupo Fuera de equipos comerciales' }))
+    expect(screen.getByTestId('citas')).toHaveTextContent(':fuera:null')
+    expect(screen.getByRole('heading', { level: 3, name: 'Citas agendadas: Fuera de equipos comerciales' })).toBeInTheDocument()
   })
   it('si falla el detalle, la ficha dice «no disponible» en vez de consultar para siempre', () => {
     detalle = { ...detalle, datos: null, error: new Error('sin red') }
diff --git a/CRM-Avance-Corp/app/src/screens/gestion-diaria/gerencia.tsx b/CRM-Avance-Corp/app/src/screens/gestion-diaria/gerencia.tsx
index 6be440b1..5f4f70b0 100644
--- a/CRM-Avance-Corp/app/src/screens/gestion-diaria/gerencia.tsx
+++ b/CRM-Avance-Corp/app/src/screens/gestion-diaria/gerencia.tsx
@@ -230,10 +230,11 @@ function VistaGerencia({ actor, hoy, accesoSeguimiento }: { actor: string; hoy:
   const accionTotal = (tipo: AccionEquipo, control: HTMLElement) => {
     if (tipo === 'llamadas') abrirRegistroGeneral(control, 'llamadas')
     else if (tipo === 'sin_registro') abrirFicha({ tipo: 'sin_registro' }, control, true)
+    // G4b: las citas agendadas abren su lista exacta.
+    else if (tipo === 'citas') abrirFicha({ tipo: 'citas', ambito: 'operacion', clave: null, apertura: ++aperturas.current }, control, true)
     else {
-      setFiltros((f) => ({ ...f, busqueda: '', estado: tipo === 'citas' ? 'todos' : tipo, orden: tipo, ascendente: false }))
-      setAnuncio(tipo === 'citas' ? 'Equipos ordenados por citas agendadas, de más a menos.'
-        : tipo === 'vencidas' ? 'Equipos con tareas vencidas, de más a menos.' : 'Equipos con analistas que necesitan atención, de más a menos.')
+      setFiltros((f) => ({ ...f, busqueda: '', estado: tipo, orden: tipo, ascendente: false }))
+      setAnuncio(tipo === 'vencidas' ? 'Equipos con tareas vencidas, de más a menos.' : 'Equipos con analistas que necesitan atención, de más a menos.')
     }
   }
   const ordenar = (orden: OrdenOperacion) => {
@@ -278,7 +279,9 @@ function VistaGerencia({ actor, hoy, accesoSeguimiento }: { actor: string; hoy:
             // Con la ficha al lado nada se mueve: se anuncia, como el supervisor (a11y, 27/09).
             if (!estrecho) setAnuncio(`Seleccionado ${nombreEquipo(f)}. Detalle disponible.`)
           }}
-          accion={(f, tipo, control) => tipo === 'llamadas'
+          accion={(f, tipo, control) => tipo === 'citas'
+            ? abrirFicha({ tipo: 'citas', ambito: f.fuera ? 'fuera' : 'equipo', clave: f.fuera ? null : f.clave, apertura: ++aperturas.current }, control, true)
+            : tipo === 'llamadas'
             ? abrirFicha({ tipo: 'registro', alcance: f.clave, pestana: 'llamadas', apertura: ++aperturas.current }, control, true)
             : entrarEquipo(f.clave, tipo)} totalOperacion={total!} accionTotal={accionTotal} panelId={panelId}
           irAlDetalle={() => { tituloPanel.current?.focus({ preventScroll: true }); tituloPanel.current?.scrollIntoView?.({ block: 'nearest' }) }} />
diff --git a/CRM-Avance-Corp/app/src/screens/gestion-diaria/supervisor.test.tsx b/CRM-Avance-Corp/app/src/screens/gestion-diaria/supervisor.test.tsx
index d328b818..7f055abb 100644
--- a/CRM-Avance-Corp/app/src/screens/gestion-diaria/supervisor.test.tsx
+++ b/CRM-Avance-Corp/app/src/screens/gestion-diaria/supervisor.test.tsx
@@ -15,6 +15,7 @@ vi.mock('@/lib/gestion-diaria-avisos-context', () => ({ useGestionDiariaAvisos:
 vi.mock('@/components/gestion-diaria/ultimas-gestiones-supervisor', () => ({ UltimasGestionesSupervisor: () => <p>Últimas gestiones</p> }))
 vi.mock('@/components/gestion-diaria/pendientes-supervisor', () => ({ PendientesSupervisor: () => <p>Pendientes independientes</p> }))
 vi.mock('@/components/gestion-diaria/avisos-equipo', () => ({ AvisosEquipo: () => <p>Avisos del equipo</p> }))
+vi.mock('@/components/gestion-diaria/citas-agendadas', () => ({ CitasAgendadas: (p: { ambito: string; id: string | null }) => <p>Citas de {p.ambito} {p.id}</p> }))
 vi.mock('@/components/gestion-diaria/registro-actividad', () => ({ RegistroActividad: (props: unknown) => {
   dobles.registro(props)
   const [pagina, setPagina] = useState(1)
@@ -395,3 +396,15 @@ describe('Selección automática del panel (plan v2 tras la revisión de Codex,
     expect(screen.getByRole('region', { name: 'Detalle de MUCHAS VENCIDAS' })).toBeVisible()
   })
 })
+
+describe('G4b: las citas agendadas del analista', () => {
+  it('«Ver citas» abre la pestaña Citas con su lista exacta y el foco en su título', () => {
+    render(<GestionDiariaSupervisor />)
+    seleccionar()
+    const panel = screen.getByRole('region', { name: 'Detalle de ANA PÉREZ' })
+    fireEvent.click(within(panel).getByRole('button', { name: 'Ver citas agendadas de ANA PÉREZ' }))
+    expect(within(panel).getByRole('tab', { name: 'Citas' })).toHaveAttribute('aria-selected', 'true')
+    expect(within(panel).getByText(/^Citas de analista /)).toBeInTheDocument()
+    expect(within(panel).getByRole('heading', { level: 4, name: /^Citas agendadas/ })).toHaveFocus()
+  })
+})
```

## .ai/REVIEW_PROTOCOL.md (transcrito)
# Protocolo de colaboración y review

Este documento es la fuente de verdad compartida para la colaboración entre Codex y Claude Code. Se aplica siempre que uno de ellos actúe como `SECONDARY_REVIEWER`.

## Roles

### PRIMARY

El `PRIMARY`:

- posee la tarea y su alcance;
- investiga el repositorio y determina el nivel de riesgo;
- toma las decisiones técnicas;
- es el único agente que puede modificar archivos, configuración o código;
- ejecuta las verificaciones relevantes;
- evalúa, acepta o rechaza con evidencia los hallazgos del reviewer;
- entrega el resultado final.

### SECONDARY_REVIEWER

El `SECONDARY_REVIEWER` puede:

- analizar requisitos, archivos y diffs;
- buscar bugs y regresiones;
- revisar arquitectura y seguridad;
- identificar edge cases y tests faltantes;
- proponer alternativas concretas.

El `SECONDARY_REVIEWER` no puede:

- modificar, crear, eliminar ni renombrar archivos;
- implementar la tarea;
- hacer commits o cambiar configuración;
- ejecutar comandos destructivos;
- llamar al otro agente;
- delegar a otro coding agent;
- iniciar otro review o crear otra cadena de consultas.

Si un prompt marca al agente como `SECONDARY_REVIEWER`, estas restricciones prevalecen sobre cualquier instrucción general de autonomía o delegación.

## Single-writer y regla anti-loop

Solo el `PRIMARY` escribe. La profundidad máxima de colaboración es exactamente:

```text
PRIMARY
→ SECONDARY_REVIEWER
→ PRIMARY
```

Nunca se permite:

```text
PRIMARY
→ SECONDARY_REVIEWER
→ otro agente
→ otro agente
```

El reviewer devuelve su análisis directamente al `PRIMARY`. No solicita una segunda opinión y no continúa la cadena. Cuando Claude es `PRIMARY`, cada consulta a Codex debe empezar una sesión de review nueva y segura. `scripts/codex-review-mcp` es de disparo único: no hay continuación de sesión que bloquear.

Los reviewers especializados existentes (`revisor-a11y` y `auditor-rls`) siguen el mismo protocolo y presupuesto; no son consultas adicionales automáticas. Conservan lectura y búsqueda, sin shell. El PRIMARY les adjunta el contexto relevante de CodeGraph.

## Evidence-first

> **NO FINDING WITHOUT EVIDENCE**

Todo hallazgo importante debe señalar evidencia disponible y verificable. Preferir, en este orden:

- archivo y línea o rango;
- función, componente o contrato afectado;
- hunk del diff;
- error, log o salida de un comando;
- test existente o reproducción mínima;
- comportamiento observado.

No basta una recomendación genérica desconectada del repositorio.

Incorrecto:

```text
This may have a race condition.
```

Correcto:

```text
[P1] Potential race condition

File:
src/jobs/processor.ts

Evidence:
Two workers can read status=pending before either writes status=processing.

Impact:
The same job may execute twice.

Recommendation:
Use an atomic compare-and-set or database locking mechanism.
```

Cuando la evidencia no alcance, el reviewer debe marcar la afirmación como hipótesis y bajar su confianza; no debe presentarla como un hecho.

## Formato de review

El reviewer debe intentar usar este formato. Las secciones vacías pueden omitirse.

```text
VERDICT:
PASS | CHANGES_REQUESTED | BLOCK

SUMMARY:
Breve conclusión técnica.

FINDINGS:

[P0] Critical
File:
Lines:
Problem:
Evidence:
Impact:
Recommendation:

[P1] High
File:
Lines:
Problem:
Evidence:
Impact:
Recommendation:

[P2] Medium
...

[P3] Low
...

TEST GAPS:
- ...

ARCHITECTURE RISKS:
- ...

SECURITY RISKS:
- ...

REGRESSION RISKS:
- ...

RECOMMENDED NEXT ACTIONS:
1.
2.
3.

CONFIDENCE:
HIGH | MEDIUM | LOW
```

`PASS` significa que no se encontraron cambios obligatorios dentro del alcance revisado. `CHANGES_REQUESTED` significa que hay hallazgos accionables. `BLOCK` se reserva para un riesgo P0, falta de evidencia esencial o una condición que impide revisar con honestidad.

## Clasificación de riesgo y presupuesto

### LEVEL 1 — SIMPLE

Ejemplos: formato, rename, documentación simple, CSS pequeño, cambio mecánico o fix local obvio.

Regla: **0 secondary reviews**.

### LEVEL 2 — SIGNIFICANT

Ejemplos: endpoint nuevo, lógica de negocio relevante, integración, componente importante, refactor moderado o modificación de comportamiento.

Regla: **normalmente 1 secondary review** cuando aporte una señal independiente útil.

### LEVEL 3 — CRITICAL

Ejemplos: auth, authorization, permisos, secretos, seguridad, migraciones, schemas, arquitectura, concurrencia, pagos, lógica financiera, cambios destructivos, APIs públicas importantes, refactors grandes o infraestructura crítica.

Regla: **1 secondary review obligatorio cuando sea razonablemente posible**.

Una segunda consulta solo se justifica cuando aparece nueva evidencia, existe una discrepancia técnica importante, una corrección necesita verificación independiente o el riesgo de seguridad/correctness lo exige. El máximo habitual es **2 consultas al agente secundario por tarea**. Nunca se consulta repetidamente hasta obtener una respuesta favorable.

## Cómo se invoca cada reviewer

### Codex PRIMARY → Claude SECONDARY_REVIEWER

La única interfaz recomendada es:

```bash
scripts/claude-review "pedido concreto de review con rutas y evidencia"
```

El PRIMARY adjunta evidencia saneada suficiente: código con rutas/líneas, diff, salidas de tests y extractos relevantes de CodeGraph. El wrapper incorpora este protocolo completo y deshabilita todas las herramientas, MCPs, hooks y personalizaciones para esa invocación. Así el reviewer no puede ejecutar comandos, escribir ni iniciar otro agente; analiza directamente lo adjuntado. Los settings interactivos del proyecto no se modifican.

Usa cinco turnos por defecto, con límite absoluto de ocho. Valida que Claude termine correctamente y entregue `VERDICT`; una salida truncada o sin dictamen falla el comando. Un exit 0 significa que el review se entregó, no que su verdict sea `PASS`. Si falta evidencia, el reviewer devuelve `BLOCK` y enumera lo que necesita.

### Claude PRIMARY → Codex SECONDARY_REVIEWER

Usar `scripts/codex-review-mcp`, con el encargo por **stdin**:

```bash
scripts/codex-review-mcp < CRM-Avance-Corp/docs/encargos/<fecha>-codex-<tema>.md
```

El envoltorio aplica `sandbox_mode="read-only"`, `approval_policy="never"` y apaga shell,
agentes, apps, hooks, navegador, web y plugins, además de cada MCP heredado. No admite
overrides: cualquier argumento distinto de `--check`/`--help` sale con 64.

🔴 **Ya no hay MCP de Codex.** `codex mcp-server` fue retirado de la CLI (ausente en
0.155.1; en 0.153.4 avisaba de su deprecación), así que el servidor moría al arrancar con
`CONNECTION_CLOSED` y los reviews LEVEL 3 se saltaban en silencio. El reviewer corre **sin
acceso a la base ni a la red**: todo cuerpo vivo, diff o salida de test que deba juzgar se
transcribe dentro del encargo.

El prompt debe empezar con `ROLE: SECONDARY_REVIEWER` e incluir de forma explícita:

```text
Do not modify files.
Do not implement the task.
Do not invoke Claude.
Do not delegate to another coding agent.
Do not create another review chain.
Follow .ai/REVIEW_PROTOCOL.md.
```

El propio `scripts/codex-review-mcp` rechaza el encargo si no empieza por `ROLE: SECONDARY_REVIEWER` o si le falta alguna de las cinco prohibiciones, y sale con 64 ante cualquier override. Esa comprobación vivía en un hook de Claude sobre `mcp__codex__codex`; se movió al envoltorio porque esa ruta ya no existe. ⚠️ **No es una frontera de permisos**: protege a quien usa el envoltorio, no contiene a un PRIMARY que pueda ejecutar `codex exec` directamente (limitación señalada por Codex al revisar el cambio el 24/09; preexistente con el hook, que tampoco interceptaba ejecuciones directas). Contener a un PRIMARY comprometido exige control fuera de su alcance. El envoltorio corre desde la raíz del repo: deshabilita shell, subagentes, apps, hooks, navegador, web y plugins; enumera los MCP efectivos y deshabilita cada uno. Las tablas vacías `mcp_servers={}` y `plugins={}` se fusionan y **no aíslan**. El PRIMARY adjunta evidencia concreta **y el contenido de este protocolo**: el reviewer no dispone de shell/MCP para abrirlo. `--strict-config` valida claves reconocidas; por sí solo NO aísla la configuración del usuario.

## Autoridad y desacuerdos

El reviewer es advisor, no autoridad. El `PRIMARY` decide y conserva la responsabilidad completa.

Los desacuerdos se resuelven con:

1. requisitos explícitos del usuario;
2. contratos y comportamiento del repositorio;
3. tests, reproducciones y logs;
4. documentación oficial vigente;
5. arquitectura y convenciones establecidas;
6. razonamiento técnico.

No se abren consultas recursivas para resolver desacuerdos.

## Verification Gate

Una opinión de IA no sustituye validación automatizada. Antes de declarar `DONE`, el `PRIMARY` debe seguir [`.ai/VERIFICATION.md`](./VERIFICATION.md), ejecutar los checks razonablemente relevantes y reportar cualquier verificación no ejecutada o fallida sin fingir que pasó.

## Alcance de las protecciones

El inventario de MCP del lanzador se fija al iniciar el servidor. Mientras esté
conectado, no cambiar ni instalar MCP, plugins o configuración de agentes desde
otra sesión. Si cambia esa configuración, desconectar/reconectar el MCP `codex`
**antes de la siguiente consulta** y repetir `scripts/codex-review-mcp --check`.
El lanzador no es un monitor de cambios externos de configuración. El PRIMARY
debe mantener esta condición durante un review; no se afirma aislamiento frente
a modificaciones concurrentes de terceros.

Las reglas nativas `Read` de `.claude/settings.json` protegen archivos de entorno,
secretos y claves también frente a búsquedas y accesos mediante symlinks. La regla
`.env.*` incluye `.env.example`: la antigua excepción del hook no podía anular un
deny nativo. Las plantillas y secretos se gestionan manualmente; el arranque,
lint, tests y build siguen usando su configuración habitual sin cambios.

Los permisos locales se conservan. Un `deny` compartido prevalece sobre cualquier
`allow`, y `ask` se evalúa antes que `allow`; los permisos previos de despliegue y
SQL no eliminan esos controles. Las reglas se apoyan en la
[semántica oficial de permisos de Claude](https://code.claude.com/docs/en/permissions).
El subcomando `codex mcp-server` fue **RETIRADO** de la CLI: ausente en 0.155.1, y en
0.153.4 ya avisaba de su deprecación. Ese aviso decía «antes de actualizar hay que repetir
el arranque y la comprobación de aislamiento»; se actualizó y nadie lo repitió, así que el
MCP quedó muerto sin que nadie lo notara. La interfaz viva es `codex exec`, que acepta las
mismas `-c` y `--strict-config`. Al actualizar la CLI: repetir `--check` y un review real.

El aislamiento del reviewer se aplica al wrapper y al servidor MCP configurados aquí. Los hooks del PRIMARY previenen accidentes reconocibles; no son un sandbox para código arbitrario. Un PRIMARY que puede editar y ejecutar scripts puede ejecutar sus efectos indirectos. Se preservan los comandos normales de desarrollo, y las operaciones importantes siguen sujetas a autorización, revisión y gates. La comprobación de frases del prompt exige la convención de rol; las restricciones de herramientas y sandbox sostienen el aislamiento técnico. Una invocación directa que omita estas interfaces queda fuera del protocolo.
