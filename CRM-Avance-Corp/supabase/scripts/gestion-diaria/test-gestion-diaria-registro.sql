-- Oráculo del registro crudo de Gestión Diaria (Fase 1) sobre la copia del banco.
-- Se ejecuta como postgres; cada lectura cambia de identidad con
-- request.jwt.claim.sub + role authenticated, como haría PostgREST. Termina con
-- GESTION_DIARIA_REGISTRO_OK o revienta con el nombre de la comprobación.
-- Los actores se DESCUBREN del fixture (no hay uuids fijos): gerencia, el
-- supervisor con un supervisor anidado debajo, un analista con actividades, un
-- analista de OTRO equipo, el coordinador, el directorio y el analista inactivo.
begin;
set local statement_timeout = '60s';

create temporary table oraculo_actores on commit drop as
select
  (select perfil_id from crm.equipo where rol_crm = 'gerencia' and activo limit 1) as ger,
  (select e.perfil_id from crm.equipo e where e.rol_crm = 'supervisor' and e.activo
     and exists (select 1 from crm.equipo h where h.supervisor_id = e.perfil_id and h.rol_crm = 'supervisor') limit 1) as sup1,
  (select e.perfil_id from crm.equipo e where e.rol_crm = 'supervisor' and e.activo and e.supervisor_id is null
     and not exists (select 1 from crm.equipo h where h.supervisor_id = e.perfil_id and h.rol_crm = 'supervisor') limit 1) as sup2,
  (select perfil_id from crm.equipo where rol_crm = 'coordinador' and activo limit 1) as coord,
  (select id from public.perfiles where rol = 'directorio' and activo limit 1) as dir,
  (select perfil_id from crm.equipo where rol_crm = 'vendedor' and not activo limit 1) as inactivo;

-- El subárbol de sup1 (él incluido, históricos incluidos) calculado APARTE de
-- los helpers del servidor: dos fuentes, un oráculo.
create temporary table oraculo_subarbol on commit drop as
with recursive arbol as (
  select o.sup1 as perfil_id from oraculo_actores o
  union
  select e.perfil_id from crm.equipo e join arbol t on e.supervisor_id = t.perfil_id
)
select perfil_id from arbol;

-- El analista con más actividades del subárbol de sup1, y uno del equipo de sup2.
create temporary table oraculo_analistas on commit drop as
select
  (select e.perfil_id from crm.equipo e, oraculo_actores o
     where e.rol_crm = 'vendedor' and e.activo and e.perfil_id in (select perfil_id from oraculo_subarbol)
     order by (select count(*) from crm.actividades a where a.creado_por = e.perfil_id) desc limit 1) as v1,
  (select e.perfil_id from crm.equipo e, oraculo_actores o
     where e.rol_crm = 'vendedor' and e.activo and e.supervisor_id = o.sup2 limit 1) as v_ajeno,
  (select e.perfil_id from crm.equipo e, oraculo_actores o
     where e.rol_crm = 'vendedor' and e.activo and e.supervisor_id <> o.sup1
       and e.perfil_id in (select perfil_id from oraculo_subarbol) limit 1) as v_anidado;

do $fixture$
declare a oraculo_actores; n oraculo_analistas;
begin
  select * into a from oraculo_actores; select * into n from oraculo_analistas;
  if a.ger is null or a.sup1 is null or a.sup2 is null or a.coord is null or a.dir is null or a.inactivo is null
     or n.v1 is null or n.v_ajeno is null or n.v_anidado is null then
    raise exception 'FIXTURE: faltan actores (ger %, sup1 %, sup2 %, coord %, dir %, inactivo %, v1 %, v_ajeno %, v_anidado %)',
      a.ger, a.sup1, a.sup2, a.coord, a.dir, a.inactivo, n.v1, n.v_ajeno, n.v_anidado;
  end if;
end $fixture$;

-- Lo ESPERADO se calcula como superusuario con la MISMA regla que la policy
-- (dueño actual del lead), nunca con la función bajo prueba.
-- La ventana del oráculo: como mucho un año (tope de la puerta), acotada a lo
-- que el fixture tenga. Lo esperado se calcula sobre la MISMA ventana Lima.
create temporary table oraculo_rango on commit drop as
select greatest((min(creado_en) at time zone 'America/Lima')::date, (now() at time zone 'America/Lima')::date - 365) as desde,
       (now() at time zone 'America/Lima')::date as hasta
from crm.actividades;
create temporary table oraculo_esperado on commit drop as
select a.id, a.creado_por, a.lead_id, a.tipo, a.creado_en, l.vendedor_id, l.asignado_supervisor_id, l.etapa
from crm.actividades a join crm.leads l on l.id = a.lead_id, oraculo_rango r
where l.activo
  and a.creado_en >= (r.desde::timestamp) at time zone 'America/Lima'
  and a.creado_en <  ((r.hasta + 1)::timestamp) at time zone 'America/Lima';

grant select on oraculo_actores, oraculo_analistas, oraculo_esperado, oraculo_rango, oraculo_subarbol to authenticated;

set local role authenticated;
do $oraculo$
declare
  a oraculo_actores; n oraculo_analistas; r oraculo_rango;
  v jsonb; v_ids uuid[]; v_esperados uuid[]; v_sub uuid[];
  v_cursor_en timestamptz; v_cursor_id uuid; v_pagina jsonb; v_vueltas integer; v_total integer;
  v_estado text;
  procedure_ok boolean;
begin
  select * into a from oraculo_actores; select * into n from oraculo_analistas; select * into r from oraculo_rango;

  -- ── A. Validaciones del input: siempre 22023 y antes de leer nada ──────────
  perform set_config('request.jwt.claim.sub', a.ger::text, true);
  for v_estado in select unnest(array[
    format('crm.registro_actividad_fn(%L, %L)', r.hasta, r.desde),                          -- desde > hasta
    format('crm.registro_actividad_fn(%L, %L)', r.hasta, r.hasta + 1),                      -- futuro
    format('crm.registro_actividad_fn(%L, %L)', r.hasta - 366, r.hasta),                    -- 367 días: el primero fuera de rango
    format('crm.registro_actividad_fn(%L, %L, p_limite => 0)', r.desde, r.hasta),           -- límite 0
    format('crm.registro_actividad_fn(%L, %L, p_limite => 501)', r.desde, r.hasta),         -- límite 501
    format('crm.registro_actividad_fn(%L, %L, p_antes_de => now())', r.desde, r.hasta),     -- cursor a medias
    format('crm.registro_actividad_fn(%L, %L, p_tipos => array[''fax''])', r.desde, r.hasta),
    format('crm.registro_actividad_fn(%L, %L, p_etapa => ''ganado'')', r.desde, r.hasta),
    format('crm.registro_actividad_fn(%L, %L, p_analista_ids => ''{}''::uuid[])', r.desde, r.hasta),
    format('crm.registro_actividad_fn(%L, %L, p_tipos => ''{}''::text[])', r.desde, r.hasta)
  ]) loop
    begin
      execute 'select ' || v_estado into v;
      raise exception 'A: debió fallar con 22023: %', v_estado;
    exception when others then
      if sqlstate <> '22023' then raise exception 'A: % falló con % (%), no con 22023', v_estado, sqlstate, sqlerrm; end if;
    end;
  end loop;

  -- ── B. Coordinador y analista INACTIVO: 42501 explícito, nunca vacío ───────
  foreach v_estado in array array[a.coord::text, a.inactivo::text] loop
    perform set_config('request.jwt.claim.sub', v_estado, true);
    begin
      v := crm.registro_actividad_fn(r.desde, r.hasta);
      raise exception 'B: % debió recibir 42501 y recibió % items', v_estado, jsonb_array_length(v->'items');
    exception when others then
      if sqlstate <> '42501' then raise exception 'B: % falló con % (%), no con 42501', v_estado, sqlstate, sqlerrm; end if;
    end;
  end loop;

  -- ── C. Gerencia y directorio ven TODO lo de leads activos ──────────────────
  select array_agg(id order by id) into v_esperados from oraculo_esperado;
  foreach v_estado in array array[a.ger::text, a.dir::text] loop
    perform set_config('request.jwt.claim.sub', v_estado, true);
    v := crm.registro_actividad_fn(r.desde, r.hasta, p_limite => 500);
    select array_agg((i->>'id')::uuid order by (i->>'id')::uuid) into v_ids from jsonb_array_elements(v->'items') i;
    if v_ids is distinct from v_esperados then
      raise exception 'C: % ve % actividades y el oráculo esperaba %', v_estado, coalesce(cardinality(v_ids), 0), cardinality(v_esperados);
    end if;
    if v->>'zona' <> 'America/Lima' or (v->>'version')::int <> 1 or v->>'generado_en' is null then
      raise exception 'C: sobre incompleto: %', v - 'items';
    end if;
  end loop;

  -- ── D. Analista: solo lo suyo, y solo puede pedir su propio id ─────────────
  perform set_config('request.jwt.claim.sub', n.v1::text, true);
  select array_agg(id order by id) into v_esperados from oraculo_esperado where vendedor_id = n.v1 and creado_por = n.v1;
  v := crm.registro_actividad_fn(r.desde, r.hasta, p_analista_ids => array[n.v1], p_limite => 500);
  select array_agg((i->>'id')::uuid order by (i->>'id')::uuid) into v_ids from jsonb_array_elements(v->'items') i;
  if v_ids is distinct from v_esperados then
    raise exception 'D: el analista ve % actividades propias y se esperaban %', coalesce(cardinality(v_ids), 0), coalesce(cardinality(v_esperados), 0);
  end if;
  if exists (select 1 from jsonb_array_elements(v->'items') i where (i->>'creado_por')::uuid <> n.v1) then
    raise exception 'D: una fila no es del analista';
  end if;
  begin
    v := crm.registro_actividad_fn(r.desde, r.hasta, p_analista_ids => array[n.v_ajeno]);
    raise exception 'D: el analista pudo pedir el registro de un colega';
  exception when others then
    if sqlstate <> '42501' then raise exception 'D: analista ajeno falló con % (%), no con 42501', sqlstate, sqlerrm; end if;
  end;

  -- ── E/F. Supervisor: su subárbol (anidado incluido), nunca otro equipo ──────
  perform set_config('request.jwt.claim.sub', a.sup1::text, true);
  v_sub := array(select perfil_id from oraculo_subarbol);
  select array_agg(id order by id) into v_esperados from oraculo_esperado
   where vendedor_id = any (v_sub) or (vendedor_id is null and asignado_supervisor_id = any (v_sub));
  v := crm.registro_actividad_fn(r.desde, r.hasta, p_limite => 500);
  select array_agg((i->>'id')::uuid order by (i->>'id')::uuid) into v_ids from jsonb_array_elements(v->'items') i;
  if v_ids is distinct from v_esperados then
    raise exception 'F: el supervisor ve % actividades y se esperaban % (subárbol de %)', coalesce(cardinality(v_ids), 0), coalesce(cardinality(v_esperados), 0), cardinality(v_sub);
  end if;
  v := crm.registro_actividad_fn(r.desde, r.hasta, p_analista_ids => array[n.v_anidado], p_limite => 500);   -- anidado: permitido
  begin
    v := crm.registro_actividad_fn(r.desde, r.hasta, p_analista_ids => array[n.v1, n.v_ajeno]);
    raise exception 'E: el supervisor pudo pedir un analista de otro equipo';
  exception when others then
    if sqlstate <> '42501' then raise exception 'E: otro equipo falló con % (%), no con 42501', sqlstate, sqlerrm; end if;
  end;

  -- ── H. Cursor: las páginas de gerencia cubren todo, sin repetir ni saltar ──
  perform set_config('request.jwt.claim.sub', a.ger::text, true);
  select array_agg(id order by id) into v_esperados from oraculo_esperado;
  v_ids := '{}'; v_cursor_en := null; v_cursor_id := null; v_vueltas := 0;
  loop
    v_pagina := crm.registro_actividad_fn(r.desde, r.hasta, p_limite => 7, p_antes_de => v_cursor_en, p_antes_id => v_cursor_id);
    v_total := jsonb_array_length(v_pagina->'items');
    exit when v_total = 0;
    v_ids := v_ids || array(select (i->>'id')::uuid from jsonb_array_elements(v_pagina->'items') i);
    -- Orden estricto dentro de la página: creado_en desc, id asc.
    if exists (
      select 1 from jsonb_array_elements(v_pagina->'items') with ordinality t(i, o)
      join jsonb_array_elements(v_pagina->'items') with ordinality s(j, p) on s.p = t.o + 1
      where (t.i->>'creado_en')::timestamptz < (s.j->>'creado_en')::timestamptz
         or ((t.i->>'creado_en')::timestamptz = (s.j->>'creado_en')::timestamptz and (t.i->>'id')::uuid > (s.j->>'id')::uuid)
    ) then raise exception 'H: página desordenada'; end if;
    v_cursor_en := (v_pagina->'items'->(v_total - 1)->>'creado_en')::timestamptz;
    v_cursor_id := (v_pagina->'items'->(v_total - 1)->>'id')::uuid;
    v_vueltas := v_vueltas + 1;
    if v_vueltas > 200 then raise exception 'H: el cursor no termina'; end if;
  end loop;
  if (select count(distinct x) from unnest(v_ids) x) <> cardinality(v_ids) then raise exception 'H: el cursor repitió filas'; end if;
  if (select array_agg(x order by x) from unnest(v_ids) x) is distinct from v_esperados then
    raise exception 'H: el cursor devolvió % filas y se esperaban %', cardinality(v_ids), cardinality(v_esperados);
  end if;

  -- ── I. Filtros de tipo y etapa acotan de verdad ────────────────────────────
  v := crm.registro_actividad_fn(r.desde, r.hasta, p_tipos => array['nota'], p_limite => 500);
  if exists (select 1 from jsonb_array_elements(v->'items') i where i->>'tipo' <> 'nota') then raise exception 'I: p_tipos no filtra'; end if;
  if jsonb_array_length(v->'items') <> (select count(*) from oraculo_esperado where tipo = 'nota') then raise exception 'I: p_tipos pierde filas'; end if;
  v := crm.registro_actividad_fn(r.desde, r.hasta, p_etapa => 'nuevo', p_limite => 500);
  if exists (select 1 from jsonb_array_elements(v->'items') i where i->>'lead_etapa' <> 'nuevo') then raise exception 'I: p_etapa no filtra'; end if;
  -- Ventana de un solo día: nada fuera de ese día Lima.
  v := crm.registro_actividad_fn(r.hasta, r.hasta, p_limite => 500);
  if exists (select 1 from jsonb_array_elements(v->'items') i
             where ((i->>'creado_en')::timestamptz at time zone 'America/Lima')::date <> r.hasta) then
    raise exception 'I: la ventana de un día trae otro día';
  end if;

  -- ── J. La etapa en ese momento: coherente con el propio cambio de etapa ────
  v := crm.registro_actividad_fn(r.desde, r.hasta, p_tipos => array['cambio_etapa'], p_limite => 500);
  if exists (
    select 1 from jsonb_array_elements(v->'items') i
    where i->'metadata' ? 'etapa_anterior'
      and i->>'etapa_en_ese_momento' is not null
      and i->>'etapa_en_ese_momento' <> i->'metadata'->>'etapa_anterior'
  ) then raise exception 'J: etapa_en_ese_momento no coincide con etapa_anterior del cambio'; end if;
  if exists (select 1 from jsonb_array_elements(v->'items') i where not (i ? 'metadata') or not (i ? 'autor_nombre') or not (i ? 'creado_por')) then
    raise exception 'J: faltan claves en la fila';
  end if;
  if exists (select 1 from jsonb_array_elements(v->'items') i where i->>'autor_nombre' = '—') then
    raise exception 'J: algún autor del roster salió sin nombre';
  end if;
  -- Lista blanca de metadata: ninguna clave fuera de las decididas, en ningún tipo.
  v := crm.registro_actividad_fn(r.desde, r.hasta, p_limite => 500);
  if exists (
    select 1 from jsonb_array_elements(v->'items') i, jsonb_object_keys(i->'metadata') k
    where k not in ('evento', 'resultado', 'submotivo', 'intento_n', 'etapa_anterior', 'etapa_nueva', 'automatico', 'resultado_reunion', 'modalidad', 'motivo')
  ) then raise exception 'J: metadata con claves fuera de la lista blanca'; end if;

  raise notice 'ORACULO: A-J en verde (actividades visibles por gerencia: %)', cardinality(v_esperados);
end;
$oraculo$;
reset role;

-- ── N. El caso ESCRITO: una llamada que hace avanzar el lead se ve en su etapa
--      previa, y el cambio automático queda debajo de ella en la página.
--      Se inserta como el analista real (policy actividades_insert + triggers)
--      dentro de esta transacción, que se deshace al final.
do $escrito$
declare
  a oraculo_actores; n oraculo_analistas;
  v_lead uuid; v_act uuid; v jsonb; v_fila jsonb; v_pos_llamada integer; v_pos_cambio integer;
begin
  select * into a from oraculo_actores; select * into n from oraculo_analistas;
  select l.id into v_lead from crm.leads l
   where l.vendedor_id = n.v1 and l.activo and l.etapa = 'nuevo' and coalesce(l.no_contactar, false) = false
   order by l.creado_en limit 1;
  if v_lead is null then raise exception 'N: el fixture no tiene un lead en nuevo del analista'; end if;
  perform set_config('request.jwt.claim.sub', n.v1::text, true);
  set local role authenticated;
  insert into crm.actividades (lead_id, tipo, detalle, creado_por)
  values (v_lead, 'llamada_realizada', 'Oráculo: contestó y sube a contactado', n.v1)
  returning id into v_act;
  reset role;
  if (select etapa from crm.leads where id = v_lead) <> 'contactado' then
    raise exception 'N: el trigger de avance no subió el lead a contactado';
  end if;
  perform set_config('request.jwt.claim.sub', n.v1::text, true);
  set local role authenticated;
  v := crm.registro_actividad_fn((now() at time zone 'America/Lima')::date, (now() at time zone 'America/Lima')::date,
                                  p_analista_ids => array[n.v1], p_tipos => array['llamada_realizada'], p_limite => 50);
  reset role;
  select i into v_fila from jsonb_array_elements(v->'items') i where (i->>'id')::uuid = v_act;
  if v_fila is null then raise exception 'N: la llamada recién escrita no aparece en el registro'; end if;
  if v_fila->>'etapa_en_ese_momento' is distinct from 'nuevo' or v_fila->>'lead_etapa' <> 'contactado' then
    raise exception 'N: etapa en ese momento = % (esperado nuevo), etapa actual = %', v_fila->>'etapa_en_ese_momento', v_fila->>'lead_etapa';
  end if;
  -- En «Todo», la llamada va ANTES (más reciente) que el cambio de etapa que causó.
  perform set_config('request.jwt.claim.sub', n.v1::text, true);
  set local role authenticated;
  v := crm.registro_actividad_fn((now() at time zone 'America/Lima')::date, (now() at time zone 'America/Lima')::date,
                                  p_analista_ids => array[n.v1], p_limite => 50);
  reset role;
  select t.o into v_pos_llamada from jsonb_array_elements(v->'items') with ordinality t(i, o) where (t.i->>'id')::uuid = v_act;
  select min(t.o) into v_pos_cambio from jsonb_array_elements(v->'items') with ordinality t(i, o)
   where t.i->>'tipo' = 'cambio_etapa' and (t.i->>'lead_id')::uuid = v_lead and t.i->>'etapa_en_ese_momento' = 'nuevo';
  if v_pos_llamada is null or v_pos_cambio is null or v_pos_llamada > v_pos_cambio then
    raise exception 'N: orden llamada (%) / cambio (%) incorrecto', v_pos_llamada, v_pos_cambio;
  end if;
end;
$escrito$;

-- ── K. anon: sin EXECUTE (error de autorización, no cualquier error) ─────────
do $anon$
begin
  set local role anon;
  begin
    perform crm.registro_actividad_fn(current_date, current_date);
    raise exception 'K: anon ejecutó la puerta';
  exception when insufficient_privilege then null;
  end;
  reset role;
end;
$anon$;

-- ── M. Sin contadores crudos en las funciones nuevas ─────────────────────────
do $censo$
begin
  if exists (
    select 1 from pg_proc p
    where p.oid in (
      to_regprocedure('crm.registro_actividad_fn(date,date,uuid[],text[],text,integer,timestamptz,uuid)'),
      to_regprocedure('private.registro_actividad_core(timestamptz,timestamptz,uuid[],text[],text,integer,timestamptz,uuid)'))
      and (lower(p.prosrc) like '%count(%' or lower(p.prosrc) like '%sum(1)%')
  ) then raise exception 'M: una función nueva cuenta (count( o sum(1))'; end if;
end;
$censo$;

select 'GESTION_DIARIA_REGISTRO_OK';
rollback;
