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
