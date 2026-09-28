-- G4b: lista exacta de «Citas agendadas». Datos sintéticos; lecturas como
-- authenticated/anon con identidad efectiva; todo termina en ROLLBACK.
-- Requiere la migración 20260928044910 instalada en el banco sintético G4.
-- La lista ES la cifra: se compara con el pulso, con el detalle por analista y con
-- private.gestion_diaria_llamadas, y los ámbitos de Gerencia deben PARTIR la operación.
-- Las afirmaciones son agregados sin GROUP BY, que siempre devuelven una fila: una
-- consulta que no encuentra filas FALLA en vez de pasar en vacío (Codex, 28/09).
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
  -- Supervisor retirado de la siembra (perfil inactivo: su rol efectivo es nulo).
  (select e.perfil_id from crm.equipo e join public.perfiles p on p.id = e.perfil_id
    where e.rol_crm = 'supervisor' and e.activo and not p.activo order by 1 limit 1) sup_retirado,
  gen_random_uuid() nadie,
  gen_random_uuid() inversionista,
  gen_random_uuid() l_visible, gen_random_uuid() l_oculto, gen_random_uuid() l_vacio,
  (now() at time zone 'America/Lima')::date - 1 as dia;
alter table g4b_actores add column ini timestamptz, add column fin timestamptz, add column arbol_sup1 uuid[];
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
begin perform set_config('request.jwt.claim.sub', coalesce(actor::text, ''), true); end $$;
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
create temporary table g4b_foto(etiqueta text primary key, cifra integer, ids uuid[]);
grant all on g4b_detalle, g4b_pulso, g4b_ambitos, g4b_foto to authenticated;

select pg_temp.afirmar(count(*) = 1 and bool_and(v1 is not null and sup1 is not null and ajeno is not null and sup2 is not null
  and fuera is not null and inactivo is not null and coordinador is not null and gerente is not null and global is not null
  and sup_retirado is not null),
  'faltan actores sintéticos (v1, sup1, ajeno, sup2, fuera, inactivo, coordinador, gerente, global, sup_retirado)') from g4b_actores;

-- Fixtures (sólo aquí se desactivan triggers de usuario; se restauran enseguida).
select pg_temp.como(gerente) from g4b_actores;
-- Control SLA: el banco ya trae el de producción; si faltara, una fila en «observacion».
alter table crm.sla_operacion_control disable trigger user;
insert into crm.sla_operacion_control(id, modo, revision, cambiado_en, cambiado_por)
select true, 'observacion', 0, now(), gerente from g4b_actores
where not exists (select 1 from crm.sla_operacion_control);
alter table crm.sla_operacion_control enable trigger user;
-- Postventa visible como en producción: las tres banderas de su candado (como test-g4a.sql).
alter table crm.multiempresa_flags disable trigger user;
insert into crm.multiempresa_flags(nombre, activo) values ('resolver_en_puertas', true), ('ficha_360_neutral', true), ('postventa_neutral', true)
on conflict (nombre) do update set activo = true;
alter table crm.multiempresa_flags enable trigger user;
alter table crm.equipo disable trigger user;
-- Supervisores anidados: sup2 cuelga de sup1. En el pulso, el analista de sup2 sigue en el
-- equipo de sup2 (supervisor activo MÁS CERCANO); en el árbol de sup1 también está.
update crm.equipo set supervisor_id = (select sup1 from g4b_actores) where perfil_id = (select sup2 from g4b_actores);
alter table crm.equipo enable trigger user;
update g4b_actores a set arbol_sup1 = (
  with recursive arbol as (
    select e.perfil_id from crm.equipo e where e.perfil_id = a.sup1
    union
    select e.perfil_id from crm.equipo e join arbol x on e.supervisor_id = x.perfil_id
  )
  select coalesce(array_agg(e.perfil_id order by e.perfil_id), '{}') from crm.equipo e
  where e.perfil_id in (select perfil_id from arbol) and e.activo and private.rol_crm(e.perfil_id) = 'vendedor');
-- Leads: uno del analista v1, uno de «fuera» (inaccesible para sup1, visible para Gerencia)
-- y uno de nombre en blanco (el SQL no lo enlaza: nullif(btrim(nombre), '')).
alter table crm.leads disable trigger user;
insert into crm.leads(id, nombre_completo, telefono, monto_estimado, vendedor_id)
select x.id, x.nombre, x.telefono, 25000, x.vendedor from g4b_actores a cross join lateral (values
  (a.l_visible, 'G4B LEAD VISIBLE', '+51999578101', a.v1),
  (a.l_oculto, 'G4B LEAD OCULTO', '+51999578102', a.fuera),
  (a.l_vacio, '   ', '+51999578103', a.v1)) x(id, nombre, telefono, vendedor);
alter table crm.leads enable trigger user;
alter table crm.tareas disable trigger user;
update crm.tareas set activo = false
where tipo = 'reunion' and creado_en >= (select ini - interval '1 day' from g4b_actores) and creado_en < (select fin + interval '1 day' from g4b_actores);
create temporary table g4b_citas(titulo text primary key, id uuid not null default gen_random_uuid(), dentro boolean not null);
grant select on g4b_citas to authenticated, anon;
insert into g4b_citas(titulo, dentro) values
  ('G4B V1 BORDE INICIO', true), ('G4B V1 EMPATE A', true), ('G4B V1 EMPATE B', true),
  ('G4B V1 BORDE FIN', true), ('G4B V1 COMPLETADA', true), ('G4B V1 DIA SIGUIENTE', false),
  ('G4B V1 DIA ANTERIOR', false), ('G4B V1 INACTIVA', false), ('G4B AJENO 1', true), ('G4B AJENO 2', true),
  ('G4B FUERA', true), ('G4B INACTIVO', true), ('G4B SIN AUTOR', true), ('G4B V1 REPROGRAMADA', true),
  ('G4B V1 LEAD VISIBLE', true), ('G4B V1 LEAD OCULTO', true), ('G4B V1 LEAD VACIO', true), ('G4B V1 POSTVENTA', true);
-- Cierres coherentes con tareas_cierre_reunion_coherente (resultado o motivo según el estado).
-- La cita de lead lleva el lead como sujeto; las demás, un perfil.
insert into crm.tareas(id, lead_id, perfil_id, vendedor_id, tipo, titulo, vence_en, creado_por, creado_en, estado, activo,
  modalidad_reunion, resultado_reunion, motivo_no_realizada, cancelada_por)
select c.id, x.lead, case when x.lead is null then coalesce(x.vendedor, a.gerente) end, x.vendedor, 'reunion', c.titulo,
  now() + interval '2 days', a.gerente, x.creado, x.estado, x.activo,
  'sin_clasificar', case x.estado when 'completada' then 'interesado' end,
  case x.estado when 'no_show' then 'cliente_no_asistio' when 'cancelada' then 'cancelada_cliente' when 'reprogramada' then 'reprogramada' end,
  case x.estado when 'cancelada' then 'sistema' end
from g4b_actores a
cross join lateral (values
  ('G4B V1 BORDE INICIO', a.v1, a.ini, 'pendiente', true, null::uuid),
  ('G4B V1 EMPATE A', a.v1, a.ini + interval '2 hours', 'pendiente', true, null),
  ('G4B V1 EMPATE B', a.v1, a.ini + interval '2 hours', 'pendiente', true, null),
  ('G4B V1 BORDE FIN', a.v1, a.fin - interval '1 microsecond', 'pendiente', true, null),
  ('G4B V1 COMPLETADA', a.v1, a.ini + interval '4 hours', 'completada', true, null),
  ('G4B V1 DIA SIGUIENTE', a.v1, a.fin, 'pendiente', true, null),
  ('G4B V1 DIA ANTERIOR', a.v1, a.ini - interval '1 microsecond', 'pendiente', true, null),
  ('G4B V1 INACTIVA', a.v1, a.ini + interval '3 hours', 'pendiente', false, null),
  ('G4B AJENO 1', a.ajeno, a.ini + interval '1 hour', 'pendiente', true, null),
  ('G4B AJENO 2', a.ajeno, a.ini + interval '5 hours', 'cancelada', true, null),
  ('G4B FUERA', a.fuera, a.ini + interval '6 hours', 'pendiente', true, null),
  ('G4B INACTIVO', a.inactivo, a.ini + interval '7 hours', 'no_show', true, null),
  ('G4B SIN AUTOR', null::uuid, a.ini + interval '8 hours', 'pendiente', true, null),
  ('G4B V1 REPROGRAMADA', a.v1, a.ini + interval '10 hours', 'reprogramada', true, null),
  ('G4B V1 LEAD VISIBLE', a.v1, a.ini + interval '11 hours', 'pendiente', true, a.l_visible),
  ('G4B V1 LEAD OCULTO', a.v1, a.ini + interval '12 hours', 'pendiente', true, a.l_oculto),
  ('G4B V1 LEAD VACIO', a.v1, a.ini + interval '13 hours', 'pendiente', true, a.l_vacio)
) as x(titulo, vendedor, creado, estado, activo, lead)
join g4b_citas c on c.titulo = x.titulo;
-- Postventa: una cita de v1 sobre un inversionista del analista «fuera».
alter table crm.inversionistas disable trigger user;
insert into crm.inversionistas(id, responsable_relacion_id, creado_por) select inversionista, fuera, gerente from g4b_actores;
alter table crm.inversionistas enable trigger user;
insert into crm.tareas(id, inversionista_id, postventa_revision, vendedor_id, tipo, titulo, vence_en, creado_por, creado_en, modalidad_reunion)
select c.id, a.inversionista, 1, a.v1, 'reunion', c.titulo, now() + interval '2 days', a.v1, a.ini + interval '9 hours', 'sin_clasificar'
from g4b_actores a join g4b_citas c on c.titulo = 'G4B V1 POSTVENTA';
alter table crm.tareas enable trigger user;

-- 1. Gerencia (banderas de postventa encendidas): la lista de cada analista es su cifra.
select pg_temp.como(gerente) from g4b_actores;
set local role authenticated;
select pg_temp.afirmar(count(*) = 1 and bool_and(private.postventa_visible(inversionista)), 'postventa visible para Gerencia con las banderas')
from g4b_actores;
insert into g4b_detalle
select (f->>'analista_id')::uuid, (f#>>'{marcador,citas_agendadas}')::integer
from g4b_actores a, jsonb_array_elements(crm.gestion_diaria_equipo_fn(a.dia, null)->'equipo') f;
select pg_temp.afirmar(count(*) = (select count(*) from crm.equipo_visible_fn() e where e.activo and e.rol_crm = 'vendedor')
    and bool_or(d.analista = a.v1) and bool_or(d.analista = a.ajeno) and bool_or(d.analista = a.fuera)
    and count(*) filter (where q.n <> d.citas) = 0,
  format('Gerencia: lista = cifra del detalle (%s analistas; distintas: %s)', count(*),
    coalesce(string_agg(format('%s (%s≠%s)', d.analista, q.n, d.citas), ', ') filter (where q.n <> d.citas), 'ninguna')))
from g4b_actores a cross join g4b_detalle d cross join lateral (select jsonb_array_length(pg_temp.lista(a.dia, 'analista', d.analista)) n) q;
-- Con las banderas, la postventa entra en la lista de v1 y en su cifra (se guarda la foto).
insert into g4b_foto select 'encendidas', d.citas, pg_temp.ids(pg_temp.lista(a.dia, 'analista', a.v1))
from g4b_actores a join g4b_detalle d on d.analista = a.v1;
select pg_temp.afirmar(count(*) = 1 and bool_and(f.ids @> array[c.id] and cardinality(f.ids) = f.cifra),
  'banderas encendidas: la postventa está en la lista de v1 y en su cifra')
from g4b_foto f cross join g4b_citas c where f.etiqueta = 'encendidas' and c.titulo = 'G4B V1 POSTVENTA';
-- Oráculo independiente (g4b_citas.dentro): la lista de v1 y la de toda la operación son
-- EXACTAMENTE las citas del día que el fixture creó dentro (con las banderas, también la postventa).
select pg_temp.afirmar(count(*) = 1 and bool_and(
  pg_temp.ids(pg_temp.lista(a.dia, 'analista', a.v1)) = (select array_agg(id order by id) from g4b_citas where dentro and titulo like 'G4B V1 %')
  and pg_temp.ids(pg_temp.lista(a.dia, 'operacion', null, 50)) = (select array_agg(id order by id) from g4b_citas where dentro)),
  'Gerencia: lista de v1 y de la operación = oráculo del fixture, exactos') from g4b_actores a;
-- Leads con ids concretos: Gerencia ve los dos leads con su nombre; el de nombre en blanco no enlaza.
select pg_temp.afirmar(count(*) = 3 and bool_and(case c.titulo
    when 'G4B V1 LEAD VISIBLE' then x->>'lead_id' = a.l_visible::text and x->>'lead_nombre' = 'G4B LEAD VISIBLE'
    when 'G4B V1 LEAD OCULTO' then x->>'lead_id' = a.l_oculto::text and x->>'lead_nombre' = 'G4B LEAD OCULTO'
    else x->'lead_id' = 'null'::jsonb and x->'lead_nombre' = 'null'::jsonb end),
  'Gerencia: leads con su id y nombre; el de nombre en blanco sin enlace')
from g4b_actores a cross join lateral jsonb_array_elements(pg_temp.lista(a.dia, 'analista', a.v1)) x
join g4b_citas c on c.id = (x->>'id')::uuid and c.titulo like 'G4B V1 LEAD%';
-- Los bordes: entra el primer instante del día y el último; salen el día anterior y el siguiente.
select pg_temp.afirmar(count(*) = 1 and bool_and(
  (select array_agg(c.titulo order by c.titulo) from g4b_citas c where c.id = any(pg_temp.ids(pg_temp.lista(a.dia, 'analista', a.v1))))
  @> array['G4B V1 BORDE FIN', 'G4B V1 BORDE INICIO', 'G4B V1 COMPLETADA', 'G4B V1 EMPATE A', 'G4B V1 EMPATE B', 'G4B V1 REPROGRAMADA']
  and not exists (select 1 from g4b_citas c where not c.dentro and c.id = any(pg_temp.ids(pg_temp.lista(a.dia, 'analista', a.v1))))),
  'bordes del día Lima, estados sin filtrar e inactiva fuera') from g4b_actores a;
-- Empate de creado_en: el orden lo decide el id.
select pg_temp.afirmar(count(*) = 1 and bool_and((select array_agg(x->>'id' order by n) from jsonb_array_elements(pg_temp.lista(a.dia, 'analista', a.v1)) with ordinality e(x, n)
    where x->>'id' in (select id::text from g4b_citas where titulo like 'G4B V1 EMPATE%'))
  = (select array_agg(id::text order by id) from g4b_citas where titulo like 'G4B V1 EMPATE%')), 'empate ordenado por id') from g4b_actores a;

-- 2. Gerencia: equipo, «fuera» y operación PARTEN la operación y son la cifra del pulso.
insert into g4b_pulso select crm.gestion_diaria_pulso_fn(dia) from g4b_actores;
insert into g4b_ambitos
select e->>'clave', (e#>>'{metricas,citas_agendadas}')::integer,
  pg_temp.lista(a.dia, case when e->>'clave' = 'fuera' then 'fuera' else 'equipo' end,
    case when e->>'clave' = 'fuera' then null else (e->>'clave')::uuid end, 3) items
from g4b_actores a, g4b_pulso, jsonb_array_elements(p->'equipos') e;
select pg_temp.afirmar(count(*) = (select jsonb_array_length(p->'equipos') from g4b_pulso)
    and bool_or(b.clave = a.sup1::text) and bool_or(b.clave = a.sup2::text) and bool_or(b.clave = 'fuera')
    and count(*) filter (where jsonb_array_length(b.items) <> b.cifra) = 0,
  format('ámbitos del pulso: lista = cifra (%s ámbitos; distintos: %s)', count(*),
    coalesce(string_agg(format('%s (%s≠%s)', b.clave, jsonb_array_length(b.items), b.cifra), ', ')
      filter (where jsonb_array_length(b.items) <> b.cifra), 'ninguno')))
from g4b_actores a cross join g4b_ambitos b;
select pg_temp.afirmar(count(*) = 1 and bool_and(pg_temp.ids(pg_temp.lista(a.dia, 'operacion', null, 5))
    = (select coalesce(array_agg(i order by i), '{}') from g4b_ambitos, unnest(pg_temp.ids(items)) i)
  and (select cardinality(array_agg(i)) from g4b_ambitos, unnest(pg_temp.ids(items)) i)
    = (select cardinality(array_agg(distinct i)) from g4b_ambitos, unnest(pg_temp.ids(items)) i)
  and jsonb_array_length(pg_temp.lista(a.dia, 'operacion', null, 5)) = (p#>>'{actual,citas_agendadas}')::integer
  and jsonb_array_length(pg_temp.lista(a.dia, 'operacion', null, 5)) > 0),
  'los equipos y «fuera» parten la operación, sin solaparse, y la operación es la cifra del pulso')
from g4b_actores a, g4b_pulso;
select pg_temp.afirmar(count(*) = 1 and bool_and(jsonb_array_length(pg_temp.lista(a.dia, 'operacion', null, 50)) = (
    select coalesce(sum(l.citas_agendadas), 0)::integer from private.gestion_diaria_llamadas(a.ini, a.fin,
      (select array_agg(x.id) from private.gestion_diaria_pulso_autores(a.ini, a.fin) x)) l)),
  'la operación es la cifra de gestion_diaria_llamadas sobre los autores del pulso') from g4b_actores a;
-- «fuera»: sin autor, autor inactivo y analista sin supervisor efectivo; nunca los de un equipo.
select pg_temp.afirmar(count(*) = 1
  and bool_and(pg_temp.ids(items) @> (select array_agg(id) from g4b_citas where titulo in ('G4B FUERA', 'G4B INACTIVO', 'G4B SIN AUTOR')))
  and bool_and(not (pg_temp.ids(items) && (select array_agg(id) from g4b_citas where titulo like 'G4B V1%' or titulo like 'G4B AJENO%'))),
  'composición de «fuera»') from g4b_ambitos where clave = 'fuera';
-- Anidados: las citas del analista de sup2 son de sup2 (el más cercano), no de sup1.
select pg_temp.afirmar(count(*) = 1 and bool_and(
  pg_temp.ids((select items from g4b_ambitos where clave = a.sup2::text)) @> (select array_agg(id) from g4b_citas where titulo like 'G4B AJENO%')
  and not (pg_temp.ids((select items from g4b_ambitos where clave = a.sup1::text)) && (select array_agg(id) from g4b_citas where titulo like 'G4B AJENO%'))),
  'supervisores anidados: gana el supervisor activo más cercano') from g4b_actores a;
-- Contrato de cada fila (con filas: no pasa en vacío).
select pg_temp.afirmar(count(*) > 0 and count(*) filter (where x->>'estado' not in ('pendiente', 'completada', 'cancelada', 'no_show', 'reprogramada')
    or x->>'vence_en' is null or x->>'creado_en' is null or ((x->>'lead_id') is null) <> ((x->>'lead_nombre') is null)) = 0
  and count(*) filter (where x->>'lead_id' is not null) >= 2,
  'forma de cada fila, con leads enlazados y sin enlazar')
from g4b_actores a cross join lateral jsonb_array_elements(pg_temp.lista(a.dia, 'operacion', null, 50)) x;
reset role;

-- 3. Supervisión: sólo el ámbito «analista» de su árbol, y su lista es su cifra.
select pg_temp.como(sup1) from g4b_actores;
set local role authenticated;
select pg_temp.afirmar(count(*) = 1 and bool_and((select count(*) from crm.leads where id = a.l_oculto) = 0
    and (select count(*) from crm.leads where id = a.l_visible) = 1),
  'sup1 ve el lead de su analista y no el de «fuera»') from g4b_actores a;
select pg_temp.afirmar(coalesce(array_agg(q.analista order by q.analista), '{}') = (select arbol_sup1 from g4b_actores)
    and count(*) filter (where q.n <> q.cifra) = 0,
  format('Supervisión: su detalle es su árbol y lista = cifra (%s analistas; distintas: %s)', count(*),
    coalesce(string_agg(format('%s (%s≠%s)', q.analista, q.n, q.cifra), ', ') filter (where q.n <> q.cifra), 'ninguna')))
from g4b_actores a cross join lateral jsonb_array_elements(crm.gestion_diaria_equipo_fn(a.dia, null)->'equipo') f
cross join lateral (select (f->>'analista_id')::uuid analista, (f#>>'{marcador,citas_agendadas}')::integer cifra,
  jsonb_array_length(pg_temp.lista(a.dia, 'analista', (f->>'analista_id')::uuid)) n) q;
-- Oráculo independiente para sup1: las citas de v1 del fixture, sin la postventa (su
-- inversionista es de «fuera», fuera de su árbol).
select pg_temp.afirmar(count(*) = 1 and bool_and(not private.postventa_visible(a.inversionista)
  and pg_temp.ids(pg_temp.lista(a.dia, 'analista', a.v1))
    = (select array_agg(id order by id) from g4b_citas where dentro and titulo like 'G4B V1 %' and titulo <> 'G4B V1 POSTVENTA')),
  'Supervisión: lista de v1 = oráculo del fixture sin la postventa, exacta') from g4b_actores a;
-- La cita con lead inaccesible sigue en la lista, sin enlace; la de nombre en blanco tampoco enlaza.
select pg_temp.afirmar(count(*) = 3 and bool_and(case c.titulo
    when 'G4B V1 LEAD VISIBLE' then x->>'lead_id' = a.l_visible::text and x->>'lead_nombre' = 'G4B LEAD VISIBLE'
    else x->'lead_id' = 'null'::jsonb and x->'lead_nombre' = 'null'::jsonb end),
  'Supervisión: lead inaccesible y nombre en blanco sin enlace; la cita, en la lista')
from g4b_actores a cross join lateral jsonb_array_elements(pg_temp.lista(a.dia, 'analista', a.v1)) x
join g4b_citas c on c.id = (x->>'id')::uuid and c.titulo like 'G4B V1 LEAD%';
select pg_temp.afirmar(count(*) = 1 and bool_and(jsonb_array_length(pg_temp.lista(a.dia, 'analista', a.ajeno)) = 2),
  'el árbol de sup1 incluye al analista de sup2 anidado') from g4b_actores a;
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
-- El borde permitido: hoy − 365 responde; hoy − 366 no.
select pg_temp.afirmar(count(*) = 1 and bool_and((crm.gestion_diaria_citas_fn((now() at time zone 'America/Lima')::date - 365, 'operacion')->>'version') = '1'),
  'hoy − 365 es un día permitido') from g4b_actores;
select pg_temp.denegada(format('select crm.gestion_diaria_citas_fn(%L, %L)', (now() at time zone 'America/Lima')::date - 366, 'operacion'), '22023');
reset role;

-- 5. Sin esta puerta: analista, coordinación, lector global, un uid sin rol y ningún uid
--    (puerta y núcleo). El rol va ANTES que los parámetros: con parámetros inválidos, 42501.
select pg_temp.como(global) from g4b_actores;
set local role authenticated;
select pg_temp.afirmar(private.es_lector_global(), 'la identidad «global» es lector global (y aun así no tiene esta puerta)');
reset role;
do $$ declare actor uuid; begin
  for actor in select unnest(array[v1, coordinador, global, nadie, null]) from g4b_actores loop
    perform pg_temp.como(actor);
    execute 'set local role authenticated';
    perform pg_temp.denegada('select crm.gestion_diaria_citas_fn(null, ''otro'', null, 0)');
    perform pg_temp.denegada('select private.gestion_diaria_citas_core(null, ''otro'', null, 0, now(), null)');
    perform pg_temp.denegada(format('select crm.gestion_diaria_citas_fn(%L, %L, %L)', (select dia from g4b_actores), 'analista', (select v1 from g4b_actores)));
    perform pg_temp.denegada(format('select crm.gestion_diaria_citas_fn(%L, %L)', (select dia from g4b_actores), 'operacion'));
    perform pg_temp.denegada(format('select private.gestion_diaria_citas_core(%L, %L, null, 25, null, null)', (select dia from g4b_actores), 'operacion'));
    execute 'reset role';
  end loop;
end $$;
set local role anon;
select pg_temp.denegada(format('select crm.gestion_diaria_citas_fn(%L, %L)', dia, 'operacion')) from g4b_actores;
reset role;

-- 6. Postventa con una bandera apagada: sale de la lista Y de la cifra, y nada más cambia.
alter table crm.multiempresa_flags disable trigger user;
update crm.multiempresa_flags set activo = false where nombre = 'postventa_neutral';
alter table crm.multiempresa_flags enable trigger user;
select pg_temp.como(gerente) from g4b_actores;
set local role authenticated;
select pg_temp.afirmar(count(*) = 1 and bool_and(not private.postventa_visible(inversionista)), 'postventa oculta para Gerencia con una bandera apagada')
from g4b_actores;
insert into g4b_foto select 'apagada', (f#>>'{marcador,citas_agendadas}')::integer, pg_temp.ids(pg_temp.lista(a.dia, 'analista', a.v1))
from g4b_actores a cross join lateral jsonb_array_elements(crm.gestion_diaria_equipo_fn(a.dia, null)->'equipo') f
where (f->>'analista_id')::uuid = a.v1;
select pg_temp.afirmar(count(*) = 1 and bool_and(not (apagada.ids @> array[c.id]) and cardinality(apagada.ids) = apagada.cifra
    and apagada.cifra = encendidas.cifra - 1
    and apagada.ids = array(select i from unnest(encendidas.ids) i where i <> c.id order by i)),
  'bandera apagada: la postventa sale de la lista y de la cifra de v1, y nada más cambia')
from g4b_foto apagada cross join g4b_foto encendidas cross join g4b_citas c
where apagada.etiqueta = 'apagada' and encendidas.etiqueta = 'encendidas' and c.titulo = 'G4B V1 POSTVENTA';
select pg_temp.afirmar(count(*) = 1 and bool_and(
  jsonb_array_length(pg_temp.lista(a.dia, 'operacion', null, 50)) = (crm.gestion_diaria_pulso_fn(a.dia)#>>'{actual,citas_agendadas}')::integer
  and not (pg_temp.ids(pg_temp.lista(a.dia, 'operacion', null, 50)) @> array[(select id from g4b_citas where titulo = 'G4B V1 POSTVENTA')])),
  'bandera apagada: la operación sigue siendo su cifra, sin la postventa') from g4b_actores a;
reset role;

-- 7. Bajas: el supervisor retirado de la siembra y, en el fixture, sup1 y el gerente dados
--    de baja en el organigrama: 42501 en la puerta y en el núcleo (el rol efectivo es nulo).
alter table crm.equipo disable trigger user;
update crm.equipo set activo = false where perfil_id in (select unnest(array[sup1, gerente]) from g4b_actores);
alter table crm.equipo enable trigger user;
do $$ declare actor uuid; begin
  for actor in select unnest(array[sup1, gerente, sup_retirado]) from g4b_actores loop
    perform pg_temp.como(actor);
    execute 'set local role authenticated';
    perform pg_temp.denegada(format('select crm.gestion_diaria_citas_fn(%L, %L, %L)', (select dia from g4b_actores), 'analista', (select v1 from g4b_actores)));
    perform pg_temp.denegada(format('select crm.gestion_diaria_citas_fn(%L, %L)', (select dia from g4b_actores), 'operacion'));
    perform pg_temp.denegada(format('select private.gestion_diaria_citas_core(%L, %L, null, 25, null, null)', (select dia from g4b_actores), 'operacion'));
    execute 'reset role';
  end loop;
end $$;

-- 8. El paraguas ejecuta el gate nuevo.
select pg_temp.afirmar(private.assert_gestion_diaria_citas() like 'OK:%' and private.assert_gestion_diaria() like '%OK: citas G4b%', 'gate G4b enchufado');
select 'G4B_OK' as resultado;
rollback;
