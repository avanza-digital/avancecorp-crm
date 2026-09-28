-- G4a: Gerencia lee pendientes de cualquier analista de la operación. Datos sintéticos;
-- lecturas como authenticated/anon con identidad efectiva; todo termina en ROLLBACK.
-- Requiere la migración 20260928043728 instalada. Casos pedidos por auditor-rls (27/09).
begin;
set local statement_timeout = '300s';
set local timezone = 'America/Lima';
do $$ begin
  if shobj_description((select oid from pg_database where datname = current_database()), 'pg_database')
    is distinct from 'BANCO SINTETICO G4 / sin produccion' then
    raise exception 'G4a: sólo en el banco sintético G4';
  end if;
end $$;

create function pg_temp.afirmar(ok boolean, mensaje text) returns void language plpgsql as $$
begin if ok is not true then raise exception 'G4a: %', mensaje; end if; end $$;
create function pg_temp.codigo(comando text) returns text language plpgsql as $$
declare recibido text; begin
  begin execute comando; exception when others then recibido := sqlstate; end;
  return coalesce(recibido, 'ninguno');
end $$;
create function pg_temp.denegada(comando text, codigo text default '42501') returns void language plpgsql as $$
declare recibido text := pg_temp.codigo(comando); begin
  perform pg_temp.afirmar(recibido = codigo, format('error esperado %s; recibido %s: %s', codigo, recibido, comando));
end $$;
create function pg_temp.como(actor uuid) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', coalesce(actor::text, ''), true); end $$;

-- Actores efectivos (como H3): supervisor con rol vigente; «ajeno» FUERA del árbol de sup1
-- (se resuelve con el propio ámbito canónico, así los anidados no cuelan); v2 se inactiva abajo.
create temporary table g4_actores as
with sups as (
  select e.perfil_id from crm.equipo e
  where private.rol_crm(e.perfil_id) = 'supervisor'
    and exists (select 1 from crm.equipo v where v.supervisor_id = e.perfil_id and private.rol_crm(v.perfil_id) = 'vendedor')
  order by e.perfil_id limit 1
), bajo as (
  select v.perfil_id from crm.equipo v, sups s
  where v.supervisor_id = s.perfil_id and private.rol_crm(v.perfil_id) = 'vendedor' order by v.perfil_id
)
select (select perfil_id from sups) sup1,
  (select perfil_id from bajo limit 1) v1,
  (select perfil_id from bajo offset 1 limit 1) v2,
  -- «Fuera» = analista activo sin supervisor EFECTIVO (nulo o con el supervisor dado de baja), como en el pulso.
  (select perfil_id from crm.equipo where private.rol_crm(perfil_id) = 'vendedor'
    and (supervisor_id is null or private.rol_crm(supervisor_id) is distinct from 'supervisor') order by perfil_id limit 1) fuera,
  (select perfil_id from crm.equipo where private.rol_crm(perfil_id) = 'coordinador' limit 1) coordinador,
  (select perfil_id from crm.equipo where private.rol_crm(perfil_id) = 'gerencia' limit 1) gerente,
  (select id from public.perfiles where activo and rol = 'directorio' limit 1) global,
  gen_random_uuid() nadie, gen_random_uuid() inversionista, null::uuid ajeno;
select pg_temp.como(sup1) from g4_actores;
set local role authenticated;
create temporary table g4_roster_sup1 as
select (r->>'analista_id')::uuid id from jsonb_array_elements(private.gestion_diaria_equipo_ambito(null)->'roster') r;
reset role;
update g4_actores set ajeno = (select e.perfil_id from crm.equipo e where private.rol_crm(e.perfil_id) = 'vendedor'
  and private.rol_crm(e.supervisor_id) = 'supervisor' and e.perfil_id not in (select id from g4_roster_sup1) order by e.perfil_id limit 1);
grant select on g4_actores to authenticated, anon;
select pg_temp.afirmar(sup1 is not null and v1 is not null and v2 is not null and ajeno is not null and fuera is not null
  and coordinador is not null and gerente is not null and global is not null,
  'faltan actores sintéticos (sup1 con dos analistas, ajeno fuera de su árbol, fuera, coordinador, gerente, global)') from g4_actores;
select pg_temp.como(global) from g4_actores;
set local role authenticated;
select pg_temp.afirmar(private.es_lector_global(), 'el actor «global» debe ser lector global efectivo');
reset role;

-- El núcleo H3 con otro nombre, acreditado por identidad (md5 de su cuerpo vivo en producción).
create function pg_temp.core_h3(
  p_analista_id uuid, p_solo_vencidas boolean, p_limite integer,
  p_despues_de timestamptz, p_despues_id uuid
) returns jsonb
language plpgsql stable security invoker set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_ambito jsonb;
  v_ahora timestamptz := statement_timestamp();
  v_respuesta jsonb;
  v_invalida boolean;
begin
  -- También protege la invocación directa del núcleo por authenticated.
  if v_uid is null or private.rol_crm(v_uid) is distinct from 'supervisor' then
    raise exception 'No autorizado para consultar pendientes' using errcode = '42501';
  end if;
  v_ambito := private.gestion_diaria_equipo_ambito(v_uid);
  if p_analista_id is null or p_solo_vencidas is null or p_limite is null
    or p_limite < 1 or p_limite > 100
    or (p_despues_de is null) <> (p_despues_id is null)
    or (p_despues_de is not null and not isfinite(p_despues_de)) then
    raise exception 'Parámetros de pendientes inválidos' using errcode = '22023';
  end if;
  if not exists (select 1 from jsonb_array_elements(v_ambito->'roster') r
    where (r->>'analista_id')::uuid = p_analista_id) then
    -- Ajeno, inactivo e inexistente tienen idéntica respuesta.
    raise exception 'No autorizado para consultar pendientes' using errcode = '42501';
  end if;

  -- Resumen y página comparten sentencia y RLS. La referencia no determina
  -- quién es responsable de la tarea ni elimina tareas sin lead visible.
  with base as materialized (
    select t.id, t.vendedor_id, t.tipo, t.titulo, t.vence_en,
      t.lead_id, t.perfil_id, t.inversionista_id
    from crm.tareas t
    where t.vendedor_id = p_analista_id and t.activo and t.estado = 'pendiente'
  ), resumen as (
    select coalesce(cardinality(array_agg(b.id)), 0) as tareas_pendientes,
      coalesce(cardinality(array_agg(b.id) filter (where b.vence_en < v_ahora)), 0) as tareas_vencidas,
      coalesce(bool_or(num_nonnulls(b.lead_id, b.perfil_id, b.inversionista_id) <> 1
        or not isfinite(b.vence_en)), false) as invalida
    from base b
  ), sonda as materialized (
    select b.* from base b
    where (not p_solo_vencidas or b.vence_en < v_ahora)
      and (p_despues_de is null or (b.vence_en, b.id) > (p_despues_de, p_despues_id))
    order by b.vence_en, b.id limit p_limite + 1
  ), pagina as materialized (
    select s.* from sonda s order by s.vence_en, s.id limit p_limite
  ), estado as (
    select coalesce(cardinality(array_agg(s.id)), 0) > p_limite as hay_mas from sonda s
  )
  select jsonb_build_object(
    'version', 1, 'zona', 'America/Lima', 'supervisor_id', v_uid,
    'analista_id', p_analista_id, 'generado_en', v_ahora, 'pendientes_al', v_ahora,
    'solo_vencidas', p_solo_vencidas, 'limite', p_limite,
    'resumen', jsonb_build_object('tareas_pendientes', r.tareas_pendientes,
      'tareas_vencidas', r.tareas_vencidas),
    'items', coalesce((select jsonb_agg(jsonb_build_object(
      'id', p.id, 'vendedor_id', p.vendedor_id, 'tipo', p.tipo, 'titulo', p.titulo,
      'vence_en', p.vence_en, 'estado', 'pendiente',
      'referencia_tipo', case when p.lead_id is not null then 'lead'
        when p.perfil_id is not null then 'perfil' else 'postventa' end,
      'lead_id', case when nullif(btrim(l.nombre_completo), '') is not null then l.id end,
      'lead_nombre', nullif(btrim(l.nombre_completo), '')
    ) order by p.vence_en, p.id) from pagina p left join crm.leads l on l.id = p.lead_id), '[]'::jsonb),
    'hay_mas', e.hay_mas,
    'siguiente_cursor', case when e.hay_mas then (select jsonb_build_object(
      'despues_de', p.vence_en, 'despues_id', p.id)
      from pagina p order by p.vence_en desc, p.id desc limit 1) else null end
  ), r.invalida into v_respuesta, v_invalida from resumen r cross join estado e;
  if v_invalida then
    raise exception 'No se pudo confirmar la integridad de las tareas' using errcode = '22000';
  end if;
  return v_respuesta;
end;
$function$;

select pg_temp.afirmar(md5(prosrc) = 'fde88f7d2cca6a912693733969391db5', 'la copia H3 de la prueba no es el cuerpo vivo')
from pg_proc where oid = 'pg_temp.core_h3(uuid,boolean,integer,timestamptz,uuid)'::regprocedure;

-- Fixtures (sólo aquí se desactivan triggers de usuario; se restauran enseguida).
alter table crm.tareas disable trigger user;
update crm.tareas set activo = false
where vendedor_id in (select unnest(array[v1, v2, ajeno, fuera]) from g4_actores);
insert into crm.tareas(perfil_id, vendedor_id, tipo, titulo, vence_en, creado_por)
select a.v1, a.v1, 'tarea', 'G4A V1 ' || i, now() - make_interval(secs => i), a.v1
from g4_actores a cross join generate_series(1, 1004) i;
insert into crm.tareas(perfil_id, vendedor_id, tipo, titulo, vence_en, creado_por)
select a.v1, a.v1, 'tarea', 'G4A V1 FUTURA', now() + interval '1 day', a.v1 from g4_actores a;
insert into crm.tareas(perfil_id, vendedor_id, tipo, titulo, vence_en, creado_por)
select x.id, x.id, 'tarea', 'G4A ' || x.etiqueta, now() - interval '1 hour', x.id
from g4_actores a cross join lateral (values (a.v2, 'V2'), (a.ajeno, 'AJENO'), (a.fuera, 'FUERA')) x(id, etiqueta);
alter table crm.inversionistas disable trigger user;
insert into crm.inversionistas(id, responsable_relacion_id, creado_por) select inversionista, ajeno, gerente from g4_actores;
alter table crm.inversionistas enable trigger user;
insert into crm.tareas(inversionista_id, postventa_revision, vendedor_id, tipo, titulo, vence_en, creado_por)
select inversionista, 1, v1, 'tarea', 'G4A POSTVENTA', now() - interval '2 hours', v1 from g4_actores;
alter table crm.tareas enable trigger user;
-- Postventa visible como en producción: las tres banderas de su candado (el banco no siembra
-- la configuración multiempresa; se ponen aquí, sin triggers, y el ROLLBACK las deshace).
alter table crm.multiempresa_flags disable trigger user;
insert into crm.multiempresa_flags(nombre, activo) values ('resolver_en_puertas', true), ('ficha_360_neutral', true), ('postventa_neutral', true)
on conflict (nombre) do update set activo = true;
alter table crm.multiempresa_flags enable trigger user;
select pg_temp.como(gerente) from g4_actores;
set local role authenticated;
select pg_temp.afirmar(private.postventa_visible(inversionista), 'postventa visible para Gerencia con las banderas') from g4_actores;
reset role;

-- 1. Supervisión: idéntica a H3 (respuesta y errores); fuera de su árbol, 42501.
select pg_temp.como(sup1) from g4_actores;
set local role authenticated;
select pg_temp.afirmar(pg_temp.core_h3(v1, false, 25, null, null) = private.gestion_diaria_pendientes_core(v1, false, 25, null, null)
  and pg_temp.core_h3(v1, true, 100, null, null) = private.gestion_diaria_pendientes_core(v1, true, 100, null, null),
  'Supervisión debe recibir la misma respuesta que con H3') from g4_actores;
select pg_temp.afirmar(pg_temp.codigo(format('select pg_temp.core_h3(%L,false,25,null,null)', x))
    = pg_temp.codigo(format('select private.gestion_diaria_pendientes_core(%L,false,25,null,null)', x)),
  'mismo error que H3 para ' || coalesce(x::text, 'null'))
from g4_actores, unnest(array[ajeno, fuera, nadie, null]) x;
select pg_temp.afirmar(pg_temp.codigo(format('select pg_temp.core_h3(%L,false,0,null,null)', v1))
  = pg_temp.codigo(format('select private.gestion_diaria_pendientes_core(%L,false,0,null,null)', v1)), 'mismo 22023 que H3') from g4_actores;
select pg_temp.afirmar(p->>'supervisor_id' = sup1::text and p->>'analista_id' = v1::text, 'la respuesta nombra a quien consulta')
from g4_actores, lateral (select crm.gestion_diaria_pendientes_fn(v1) p) q;
select pg_temp.denegada(format('select crm.gestion_diaria_pendientes_fn(%L)', x)) from g4_actores, unnest(array[ajeno, fuera, nadie]) x;
reset role;

-- 2. Gerencia: analista de un equipo, de otro equipo y de «fuera»; la respuesta nombra al gerente.
select pg_temp.como(gerente) from g4_actores;
set local role authenticated;
select pg_temp.afirmar(p->>'supervisor_id' = gerente::text and p->>'analista_id' = v1::text
  and (p#>>'{resumen,tareas_pendientes}')::int = 1006 and (p#>>'{resumen,tareas_vencidas}')::int = 1005
  and not exists (select 1 from jsonb_array_elements(p->'items') i where i->>'vendedor_id' <> v1::text),
  'Gerencia lee al analista de sup1, postventa incluida')
from g4_actores, lateral (select crm.gestion_diaria_pendientes_fn(v1) p) q;
select pg_temp.afirmar((p#>>'{resumen,tareas_pendientes}')::int = 1 and p->'items'->0->>'titulo' = 'G4A ' || etiqueta,
  'Gerencia lee a ' || etiqueta)
from g4_actores, lateral (values (ajeno, 'AJENO'), (fuera, 'FUERA')) x(id, etiqueta),
  lateral (select crm.gestion_diaria_pendientes_fn(x.id) p) q;
-- Cifra = lista: el detalle por analista que Gerencia ya ve cuenta lo mismo que la lista.
-- Agregado sin GROUP BY: siempre devuelve una fila, así la afirmación corre aunque falte el analista (Codex).
select pg_temp.afirmar(count(*) = 1 and min((f->>'tareas_pendientes')::int) = 1006 and min((f->>'tareas_vencidas')::int) = 1005,
  'cifra del detalle = lista (exactamente una fila de v1)')
from g4_actores a, jsonb_array_elements(private.gestion_diaria_equipo_core(current_date, null)->'equipo') f
where (f->>'analista_id')::uuid = a.v1;
-- Recorrido completo de 1.006 tareas en páginas de 100: once páginas, sin repetir ni saltar.
create temporary table g4_ids(id uuid primary key, item jsonb);
do $$ declare p jsonb; c_fecha timestamptz; c_id uuid; n int := 0; fila jsonb; begin
  loop
    p := crm.gestion_diaria_pendientes_fn((select v1 from g4_actores), false, 100, c_fecha, c_id);
    n := n + 1;
    for fila in select value from jsonb_array_elements(p->'items') loop
      insert into g4_ids values ((fila->>'id')::uuid, fila);
    end loop;
    exit when not (p->>'hay_mas')::boolean;
    c_fecha := (p#>>'{siguiente_cursor,despues_de}')::timestamptz; c_id := (p#>>'{siguiente_cursor,despues_id}')::uuid;
    perform pg_temp.afirmar(n < 20, 'el cursor debe terminar');
  end loop;
  perform pg_temp.afirmar(n = 11 and (select count(*) from g4_ids) = 1006, format('recorrido completo (%s páginas, %s filas)', n, (select count(*) from g4_ids)));
end $$;
select pg_temp.afirmar(count(*) = 1 and bool_and(item->>'referencia_tipo' = 'postventa' and item->'lead_id' = 'null'::jsonb),
  'la postventa está (una vez) y sin enlace inventado') from g4_ids where item->>'titulo' = 'G4A POSTVENTA';
reset role;
-- El recorrido entrega EXACTAMENTE las tareas pendientes activas de v1 (conjunto esperado leído como dueño).
select pg_temp.afirmar((select count(*) from g4_ids) = count(*) and bool_and(t.id in (select id from g4_ids)),
  'el recorrido paginado es exactamente el conjunto esperado')
from g4_actores a, crm.tareas t where t.vendedor_id = a.v1 and t.activo and t.estado = 'pendiente';
select pg_temp.como(gerente) from g4_actores;
set local role authenticated;
select pg_temp.denegada(format('select crm.gestion_diaria_pendientes_fn(%L)', nadie)) from g4_actores;
select pg_temp.denegada('select crm.gestion_diaria_pendientes_fn(null)', '22023');
select pg_temp.denegada(format('select crm.gestion_diaria_pendientes_fn(%L, false, 0)', v1), '22023') from g4_actores;
reset role;

-- 3. Postventa con una bandera apagada: ni se cuenta ni se lista, y sigue cuadrando con el detalle.
alter table crm.multiempresa_flags disable trigger user;
update crm.multiempresa_flags set activo = false where nombre = 'postventa_neutral';
alter table crm.multiempresa_flags enable trigger user;
select pg_temp.como(gerente) from g4_actores;
set local role authenticated;
select pg_temp.afirmar(count(*) = 1 and min((f->>'tareas_pendientes')::int) = 1005, 'postventa oculta: fuera de la cifra del detalle')
from g4_actores a, jsonb_array_elements(private.gestion_diaria_equipo_core(current_date, null)->'equipo') f
where (f->>'analista_id')::uuid = a.v1;
do $$ declare p jsonb; c_fecha timestamptz; c_id uuid; n int := 0; filas int := 0; begin
  loop
    p := crm.gestion_diaria_pendientes_fn((select v1 from g4_actores), false, 100, c_fecha, c_id);
    perform pg_temp.afirmar((p#>>'{resumen,tareas_pendientes}')::int = 1005, 'postventa oculta: fuera del resumen');
    perform pg_temp.afirmar(not exists (select 1 from jsonb_array_elements(p->'items') i where i->>'titulo' = 'G4A POSTVENTA'),
      'postventa oculta: en ninguna página');
    filas := filas + jsonb_array_length(p->'items'); n := n + 1;
    exit when not (p->>'hay_mas')::boolean;
    c_fecha := (p#>>'{siguiente_cursor,despues_de}')::timestamptz; c_id := (p#>>'{siguiente_cursor,despues_id}')::uuid;
    perform pg_temp.afirmar(n < 20, 'el cursor debe terminar');
  end loop;
  perform pg_temp.afirmar(filas = 1005, format('postventa oculta: %s filas en total', filas));
end $$;
reset role;

-- 4. Analista inactivo (fabricado: v2 bajo sup1, con tarea visible por RLS): 42501 para sup1 y Gerencia.
alter table crm.equipo disable trigger user;
update crm.equipo set activo = false where perfil_id = (select v2 from g4_actores);
alter table crm.equipo enable trigger user;
do $$ declare actor uuid; begin
  for actor in select unnest(array[sup1, gerente]) from g4_actores loop
    perform pg_temp.como(actor);
    execute 'set local role authenticated';
    perform pg_temp.denegada(format('select crm.gestion_diaria_pendientes_fn(%L)', (select v2 from g4_actores)));
    execute 'reset role';
  end loop;
end $$;

-- 5. Siguen sin esta puerta: analista, coordinación, lector global, uid sin rol y llamada sin identidad.
do $$ declare actor uuid; begin
  for actor in select unnest(array[v1, coordinador, global, nadie, null]) from g4_actores loop
    perform pg_temp.como(actor);
    execute 'set local role authenticated';
    perform pg_temp.denegada(format('select crm.gestion_diaria_pendientes_fn(%L)', (select ajeno from g4_actores)));
    perform pg_temp.denegada(format('select private.gestion_diaria_pendientes_core(%L,false,25,null,null)', (select ajeno from g4_actores)));
    execute 'reset role';
  end loop;
end $$;

-- 6. Gerencia desactivada (offboarding): 42501.
alter table crm.equipo disable trigger user;
update crm.equipo set activo = false where perfil_id = (select gerente from g4_actores);
alter table crm.equipo enable trigger user;
select pg_temp.como(gerente) from g4_actores;
set local role authenticated;
select pg_temp.denegada(format('select crm.gestion_diaria_pendientes_fn(%L)', v1)) from g4_actores;
reset role;

-- 7. anon no ejecuta ni la puerta ni el núcleo: primero la ACL efectiva, sin identidad de por medio (Codex);
-- después la llamada con el sub de un actor ACTIVO que sí está autorizado (sup1 → v1): el 42501 solo puede
-- venir del permiso de ejecución, no del negocio.
select pg_temp.afirmar(not has_function_privilege('anon', 'crm.gestion_diaria_pendientes_fn(uuid,boolean,integer,timestamptz,uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid)', 'EXECUTE')
  and has_function_privilege('authenticated', 'crm.gestion_diaria_pendientes_fn(uuid,boolean,integer,timestamptz,uuid)', 'EXECUTE')
  and has_function_privilege('authenticated', 'private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid)', 'EXECUTE'),
  'ACL: anon sin EXECUTE; authenticated con EXECUTE');
alter table crm.equipo disable trigger user;
update crm.equipo set activo = true where perfil_id = (select gerente from g4_actores);
alter table crm.equipo enable trigger user;
select pg_temp.como(sup1) from g4_actores;
set local role authenticated;
select pg_temp.afirmar(crm.gestion_diaria_pendientes_fn(v1)->>'analista_id' = v1::text, 'control: sup1 sí lee a v1') from g4_actores;
reset role;
set local role anon;
select pg_temp.denegada(format('select crm.gestion_diaria_pendientes_fn(%L)', v1)) from g4_actores;
select pg_temp.denegada(format('select private.gestion_diaria_pendientes_core(%L,false,25,null,null)', v1)) from g4_actores;
reset role;

-- 8. El gate completo sigue en verde con el sello nuevo.
select pg_temp.afirmar(private.assert_gestion_diaria_pendientes() like 'OK:%', 'gate H3 re-sellado');
select 'G4A_OK' as resultado;
rollback;
