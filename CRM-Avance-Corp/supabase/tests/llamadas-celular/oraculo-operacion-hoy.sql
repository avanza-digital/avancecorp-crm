-- Oráculo de la decimotercera (20261012192500, F4-e: la operación de hoy para supervisión y gerencia) sobre el banco
-- REDUCIDO de supabase/tests/llamadas-celular/base.sql. Se corre como dueño después de las doce y la decimotercera; todo
-- en una transacción que termina en ROLLBACK. Casos O1–O17 de F4E-CONTRATO.md §8, con el patrón «foto antes → acción →
-- foto después». Equipo del banco: b1 supervisa a a1 y a2 (a9 está de baja); b2 supervisa a a3; g1 es gerencia.
-- Relojes: el núcleo se llama con p_ahora = now() de la transacción; los eventos se insertan a mano con horas relativas
-- al día de Lima (el candado de eventos solo cuida update y delete) y los enlaces con su vía y su fecha (el candado los
-- valida). La salud usa el mismo now(). No sustituye el gate test-rls.mjs contra un banco con el esquema de producción.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';

create function pg_temp.como(p uuid) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', p::text, true); execute 'set local role authenticated'; end $$;
create function pg_temp.yo() returns void language plpgsql as $$
begin execute 'set local role none'; perform set_config('request.jwt.claim.sub', '', true); end $$;
-- La puerta, como el actor (reloj real).
create function pg_temp.puerta(p_actor uuid, p_sup uuid default null) returns jsonb language plpgsql as $$
declare v jsonb;
begin perform pg_temp.como(p_actor); v := crm.llamadas_celular_operacion_hoy_fn(p_sup); perform pg_temp.yo(); return v; end $$;
-- El núcleo, con el reloj fijo y la identidad del actor (el roster y el ámbito la exigen).
create function pg_temp.nucleo(p_actor uuid, p_sup uuid, p_ahora timestamptz) returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claim.sub', p_actor::text, true);
  v := private.llamadas_celular_operacion_hoy(p_actor, p_sup, p_ahora);
  perform set_config('request.jwt.claim.sub', '', true);
  return v;
end $$;
create function pg_temp.analista(p jsonb, p_id uuid) returns jsonb language sql immutable as $$
  select a from jsonb_array_elements(p -> 'analistas') a where (a ->> 'analista_id')::uuid = p_id $$;
create function pg_temp.equipo(p jsonb, p_id uuid) returns jsonb language sql immutable as $$
  select e from jsonb_array_elements(p -> 'equipos') e where (e ->> 'supervisor_id')::uuid is not distinct from p_id $$;
create function pg_temp.n(p jsonb, variadic p_ruta text[]) returns integer language sql immutable as $$
  select (p #>> p_ruta)::integer $$;
create function pg_temp.ids(p jsonb) returns uuid[] language sql immutable as $$
  select coalesce(array_agg((a ->> 'analista_id')::uuid order by (a ->> 'analista_id')::uuid), '{}')
  from jsonb_array_elements(p -> 'analistas') a $$;
-- Las cifras de un analista sin lo que sí depende de quién pregunta (a qué equipo lo cuelgan).
create function pg_temp.cifras(p jsonb) returns jsonb language sql immutable as $$ select p - 'supervisor_id' $$;
-- Suma de una clave numérica anidada a lo largo de un arreglo.
create function pg_temp.suma(p jsonb, variadic p_ruta text[]) returns integer language sql immutable as $$
  select coalesce(sum((x #>> p_ruta)::integer), 0)::integer from jsonb_array_elements(p) x $$;
-- Todas las claves y los valores de texto del jsonb, a cualquier profundidad (para la privacidad).
create function pg_temp.hojas(p jsonb) returns table(clave text, valor text) language sql immutable as $$
  with recursive w(clave, v) as (
    select null::text, p
    union all
    select x.clave, x.v
    from w, lateral (
      select e.key as clave, e.value as v
      from jsonb_each(case when jsonb_typeof(w.v) = 'object' then w.v else '{}'::jsonb end) e
      union all
      select w.clave, a.value
      from jsonb_array_elements(case when jsonb_typeof(w.v) = 'array' then w.v else '[]'::jsonb end) a
    ) x
  )
  select clave, case when jsonb_typeof(v) = 'string' then v #>> '{}' end from w $$;
-- Un id de origen válido para la v5 (C1-dddddddddd con la hora en epoch, reciente): hoy menos 2000 s, más n.
create function pg_temp.origen(p_etq text, p_n integer) returns text language sql stable as $$
  select p_etq || '-' || (floor(extract(epoch from now()))::bigint - 2000 + p_n)::text $$;
-- Un evento sintético insertado a mano. El origen vale también para la v5 (C1-dddddddddd).
create function pg_temp.evento(p_asig uuid, p_analista uuid, p_lead uuid, p_origen text, p_recibido timestamptz, p_ocurrio timestamptz,
                               p_atencion text default 'requiere_resultado', p_ident text default 'identificado', p_dir text default 'saliente')
returns uuid language plpgsql as $$
declare v uuid;
begin
  insert into crm.llamadas_celular_eventos (asignacion_id, analista_id, evento_origen_id, numero_canonico, direccion,
    recibido_en, ocurrio_en, identificacion, atencion, lead_id, metodo_asociacion, asociado_en)
  values (p_asig, p_analista, p_origen, '+51900000001', p_dir, p_recibido, p_ocurrio,
    p_ident, p_atencion, p_lead, case when p_lead is not null then 'exacto' end, case when p_lead is not null then p_recibido end)
  returning id into v;
  return v;
end $$;
-- Un resultado de llamada registrado por la encuesta (forma real), con su fecha; deshecho si se pide.
create function pg_temp.actividad(p_lead uuid, p_autor uuid, p_creado timestamptz, p_deshecha boolean default false)
returns uuid language plpgsql as $$
declare v uuid;
begin
  insert into crm.actividades (lead_id, tipo, metadata, creado_por, creado_en)
  values (p_lead, 'llamada_no_contestada',
          jsonb_build_object('evento', 'resultado_llamada', 'resultado', 'no_contesto')
            || case when p_deshecha then jsonb_build_object('deshecho_en', p_creado) else '{}'::jsonb end,
          p_autor, p_creado)
  returning id into v;
  return v;
end $$;
-- Un enlace insertado a mano con su vía y su fecha (el candado valida actividad y lead).
create function pg_temp.enlace(p_evento uuid, p_act uuid, p_lead uuid, p_autor uuid, p_via text, p_creado timestamptz)
returns uuid language plpgsql as $$
declare v uuid;
begin
  insert into crm.llamadas_celular_enlaces (evento_id, actividad_id, lead_id, enlazado_por, via, creado_en, actualizado_en)
  values (p_evento, p_act, p_lead, p_autor, p_via, p_creado, p_creado)
  returning id into v;
  return v;
end $$;
create function pg_temp.deshacer(p_act uuid) returns void language sql as $$
  update crm.actividades set metadata = metadata || jsonb_build_object('deshecho_en', now()) where id = p_act $$;

do $oraculo$
declare
  a1 constant uuid := '00000000-0000-0000-0000-0000000000a1';
  a2 constant uuid := '00000000-0000-0000-0000-0000000000a2';
  a3 constant uuid := '00000000-0000-0000-0000-0000000000a3';
  b1 constant uuid := '00000000-0000-0000-0000-0000000000b1';
  b2 constant uuid := '00000000-0000-0000-0000-0000000000b2';
  g1 constant uuid := '00000000-0000-0000-0000-0000000000f1';
  c1 constant uuid := '00000000-0000-0000-0000-0000000000c1'; -- de a1
  c3 constant uuid := '00000000-0000-0000-0000-0000000000c3'; -- de a2
  c6 constant uuid := '00000000-0000-0000-0000-0000000000c6'; -- de a1
  c8 constant uuid := '00000000-0000-0000-0000-0000000000c8'; -- de a3
  d8 constant uuid := '00000000-0000-0000-0000-0000000000d8'; -- perfil sin equipo
  d9 constant uuid := '00000000-0000-0000-0000-0000000000d9'; -- coordinador
  s2 constant uuid := '00000000-0000-0000-0000-0000000000d2'; -- supervisor anidado bajo b1 (O17)
  vv constant uuid := '00000000-0000-0000-0000-0000000000e1'; -- vendedor de s2 (O17)
  vn constant uuid := '00000000-0000-0000-0000-0000000000e2'; -- vendedor de b2 sin llamadas (O13)
  vs constant uuid := '00000000-0000-0000-0000-0000000000e3'; -- vendedor de b2 sin celular (O13)
  vi constant uuid := '00000000-0000-0000-0000-0000000000e4'; -- vendedor de b1 con perfil inactivo (no cuenta)
  si constant uuid := '00000000-0000-0000-0000-0000000000e5'; -- supervisor con perfil inactivo (22023 para gerencia)
  c9 uuid := gen_random_uuid(); -- lead de a3 que se convierte después (O9)
  c40 uuid := gen_random_uuid(); -- lead de a3 con SOLO la llamada deshecha de hace 40 días
  k1 uuid; k2 uuid; k3 uuid; k4 uuid; k5 uuid;
  v_ahora constant timestamptz := now();
  v_desde constant timestamptz := date_trunc('day', now() at time zone 'America/Lima') at time zone 'America/Lima';
  v_m constant timestamptz := now() - interval '30 seconds';      -- hoy, hace un instante
  v_ayer constant timestamptz := v_desde - interval '14 hours';    -- ayer a las 10:00 de Lima
  v_e uuid; v_act uuid; v_act2 uuid; v_en uuid; v_id uuid;
  v_g jsonb; v_b jsonb; v_a jsonb; v_x jsonb; v_antes jsonb; v_eq jsonb;
  v_ruta text[];
  v_rol text;
  v_ok integer := 0;
begin
  -- ═════ Preparación: C1 de a1, C2 de a3, C3 de a2; latidos: C1 hace 1 h (al día), C2 hace 8 h (sin latido), C3 nunca ═════
  perform pg_temp.como(g1);
  k1 := (crm.asignar_celular('C1', a1) ->> 'asignacion_id')::uuid;
  k2 := (crm.asignar_celular('C2', a3) ->> 'asignacion_id')::uuid;
  k3 := (crm.asignar_celular('C3', a2) ->> 'asignacion_id')::uuid;
  perform pg_temp.yo();
  insert into private.celulares_estado (asignacion_id, ultimo_latido_en, latido_celular_en, version_macro, eventos_en_cola) values
    (k1, now() - interval '1 hour', now() - interval '1 hour', 'llamadas-v3', 0),
    (k2, now() - interval '8 hours', now() - interval '8 hours', 'llamadas-v3', 2);

  -- Dados de baja a medias (equipo activo, perfil inactivo): un vendedor bajo b1 y un supervisor. Sin rol efectivo, no
  -- cuentan para nadie (ni como analista ni como p_supervisor_id).
  insert into public.perfiles (id, nombre_completo, rol, activo) values
    (vi, 'Vendedor Perfil Inactivo', 'comercial', false), (si, 'Supervisor Perfil Inactivo', 'comercial', false);
  insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo) values (vi, 'vendedor', b1, true), (si, 'supervisor', null, true);

  -- ═════ O1. Roles: analista, coordinador, sin equipo, anon y service_role → 42501; supervisor y gerencia → jsonb ═════
  insert into public.perfiles (id, nombre_completo, rol, activo) values
    (d9, 'Coordinador Uno', 'comercial', true), (d8, 'Sin Equipo', 'comercial', true);
  insert into crm.equipo (perfil_id, rol_crm) values (d9, 'coordinador');
  foreach v_id in array array[a1, d9, d8] loop
    begin
      perform pg_temp.puerta(v_id);
      raise exception 'ORACULO O1: % leyó la operación', v_id;
    exception when insufficient_privilege then v_ok := v_ok + 1;
    end;
  end loop;
  foreach v_rol in array array['anon', 'service_role'] loop
    begin
      execute 'set local role ' || v_rol;
      perform crm.llamadas_celular_operacion_hoy_fn();
      raise exception 'ORACULO O1: % leyó la operación', v_rol;
    exception when insufficient_privilege then v_ok := v_ok + 1;
    end;
  end loop;
  -- El núcleo exige que el actor sea el autenticado, aunque lo llame el dueño con otro id.
  begin
    perform set_config('request.jwt.claim.sub', g1::text, true);
    perform private.llamadas_celular_operacion_hoy(b1, null, v_ahora);
    raise exception 'ORACULO O1: el núcleo aceptó un actor distinto del autenticado';
  exception when insufficient_privilege then v_ok := v_ok + 1;
  end;
  v_b := pg_temp.puerta(b1);
  perform pg_temp.como(g1); v_g := crm.llamadas_celular_operacion_hoy_fn(); perform pg_temp.yo(); -- sin parámetros
  if v_b ->> 'alcance' is distinct from 'equipo' or v_g ->> 'alcance' is distinct from 'operacion'
     or v_g -> 'su_celular' is distinct from 'null'::jsonb or v_b -> 'su_celular' is distinct from '[]'::jsonb
     or (v_g ->> 'dia')::date <> (v_desde at time zone 'America/Lima')::date
     or v_g -> 'rotulos' ->> 'pendientes' is distinct from 'Sin resultado ahora (hasta 30 días)'
     or v_g -> 'rotulos' ->> 'llamadas_hoy' is distinct from 'Llamadas de hoy (por la hora de la llamada)'
     or v_g -> 'rotulos' ->> 'resultados_hoy' is distinct from 'Resultados registrados hoy (de llamadas de cualquier día)' then
    raise exception 'ORACULO O1: forma inesperada (b1 %, g1 %)', v_b, v_g;
  end if;

  -- ═════ O2. p_supervisor_id ═════
  if (pg_temp.puerta(b1, b1) - 'generado_en') <> (v_b - 'generado_en') then
    raise exception 'ORACULO O2: el supervisor con su propio id debía ver lo mismo que con nulo';
  end if;
  begin
    perform pg_temp.puerta(b1, b2);
    raise exception 'ORACULO O2: b1 leyó el equipo de b2';
  exception when insufficient_privilege then
    if sqlerrm <> 'Sin acceso a las llamadas del celular' then raise exception 'ORACULO O2: otro mensaje (%)', sqlerrm; end if;
    v_ok := v_ok + 1;
  end;
  begin
    perform pg_temp.puerta(g1, a1);
    raise exception 'ORACULO O2: gerencia con un vendedor como id';
  exception when invalid_parameter_value then
    if sqlerrm not like '%supervisor activo%' then raise exception 'ORACULO O2: otro mensaje (%)', sqlerrm; end if;
    v_ok := v_ok + 1;
  end;
  begin
    perform pg_temp.puerta(g1, si);
    raise exception 'ORACULO O2: gerencia con un supervisor de perfil inactivo como id';
  exception when invalid_parameter_value then v_ok := v_ok + 1;
  end;
  v_x := pg_temp.puerta(g1, b2);
  if pg_temp.ids(v_x) <> array[a3] or v_x ->> 'alcance' is distinct from 'equipo' or jsonb_array_length(v_x -> 'equipos') <> 1 then
    raise exception 'ORACULO O2: gerencia con b2 debía ver solo a a3 (%)', v_x;
  end if;

  -- ═════ O3. Aislamiento y claves de equipo ═════
  if pg_temp.ids(v_b) <> array[a1, a2] then raise exception 'ORACULO O3: b1 debía ver a a1 y a2, sin a3, a9 ni el de perfil inactivo (%)', pg_temp.ids(v_b); end if;
  if pg_temp.ids(pg_temp.puerta(b2)) <> array[a3] then raise exception 'ORACULO O3: b2 debía ver solo a a3'; end if;
  if pg_temp.ids(v_g) <> array[a1, a2, a3] then raise exception 'ORACULO O3: gerencia debía ver a los tres (%)', pg_temp.ids(v_g); end if;
  if jsonb_array_length(v_g -> 'equipos') <> 2
     or pg_temp.n(pg_temp.equipo(v_g, b1), 'analistas') <> 2 or pg_temp.n(pg_temp.equipo(v_g, b2), 'analistas') <> 1
     or pg_temp.equipo(v_g, b1) ->> 'supervisor_nombre' is distinct from 'Supervisor Uno' then
    raise exception 'ORACULO O3: equipos de gerencia (%)', v_g -> 'equipos';
  end if;
  if jsonb_array_length(v_b -> 'equipos') <> 1 or pg_temp.n(pg_temp.equipo(v_b, b1), 'analistas') <> 2
     or exists (select 1 from jsonb_array_elements(v_b -> 'analistas') a where (a ->> 'supervisor_id')::uuid <> b1) then
    raise exception 'ORACULO O3: el supervisor ve un único equipo con su id (%)', v_b -> 'equipos';
  end if;

  -- ═════ O4. Ingesta de hoy: una saliente identificada de a1 ═════
  v_e := pg_temp.evento(k1, a1, c1, pg_temp.origen('C1', 1), v_m + interval '20 seconds', v_m);
  v_g := pg_temp.nucleo(g1, null, v_ahora); v_a := pg_temp.analista(v_g, a1);
  if pg_temp.n(v_a, 'llamadas_hoy', 'total') <> 1 or pg_temp.n(v_a, 'llamadas_hoy', 'sin_resultado') <> 1
     or pg_temp.n(v_a, 'llamadas_hoy', 'con_resultado') <> 0 or pg_temp.n(v_a, 'pendientes', 'total') <> 1
     or pg_temp.n(v_a, 'pendientes', 'de_hoy') <> 1 or pg_temp.n(v_a, 'pendientes', 'anteriores') <> 0
     or pg_temp.n(v_a, 'pendientes', 'mas_antigua_dias') <> 0 or (v_a ->> 'sin_dato')::boolean then
    raise exception 'ORACULO O4: una saliente de hoy debía dar 1 llamada, 1 sin resultado y 1 pendiente de hoy (%)', v_a;
  end if;
  -- D4: el supervisor ve LAS MISMAS cifras de a1; el equipo y los totales son sumas.
  if pg_temp.cifras(pg_temp.analista(pg_temp.nucleo(b1, null, v_ahora), a1)) <> pg_temp.cifras(v_a) then
    raise exception 'ORACULO O4/D4: supervisor y gerencia ven cifras distintas de a1';
  end if;
  if pg_temp.n(pg_temp.equipo(v_g, b1), 'llamadas_hoy', 'total') <> 1 or pg_temp.n(v_g, 'totales', 'llamadas_hoy', 'total') <> 1
     or pg_temp.n(v_g, 'totales', 'pendientes', 'de_hoy') <> 1 then
    raise exception 'ORACULO O4: el equipo y los totales no suman la llamada (%)', v_g;
  end if;

  -- ═════ O5. Registrar al colgar (v5 con el id) ═════
  perform pg_temp.como(a1);
  v_x := crm.registrar_llamada_v5(gen_random_uuid(), c1, 'no_contesto', p_evento_origen_id => pg_temp.origen('C1', 1), p_via => 'al_colgar');
  perform pg_temp.yo();
  if v_x -> 'enlace' ->> 'estado' is distinct from 'enlazado' then raise exception 'ORACULO O5: la v5 no enlazó (%)', v_x; end if;
  v_a := pg_temp.analista(pg_temp.nucleo(g1, null, v_ahora), a1);
  if pg_temp.n(v_a, 'llamadas_hoy', 'total') <> 1 or pg_temp.n(v_a, 'llamadas_hoy', 'con_resultado') <> 1
     or pg_temp.n(v_a, 'llamadas_hoy', 'sin_resultado') <> 0 or pg_temp.n(v_a, 'resultados_hoy', 'total') <> 1
     or pg_temp.n(v_a, 'resultados_hoy', 'al_colgar') <> 1 or pg_temp.n(v_a, 'pendientes', 'total') <> 0
     or pg_temp.n(v_a, 'pendientes', 'mas_antigua_dias') is not null then
    raise exception 'ORACULO O5: registrar al colgar debía mover la llamada a con resultado y contar el resultado de hoy (%)', v_a;
  end if;

  -- ═════ O6. Borde del día en Lima ═════
  -- 23:59 de ayer recibida hoy → ayer; 00:00 de hoy → hoy; reloj 3 min adelantado en la medianoche (ocurrió 00:02 de hoy,
  -- recibida 23:59 de ayer) → hoy aunque se recibiera ayer.
  v_antes := pg_temp.analista(pg_temp.nucleo(g1, null, v_ahora), a1);
  perform pg_temp.evento(k1, a1, c1, pg_temp.origen('C1', 2), v_desde + interval '2 minutes', v_desde - interval '1 minute');
  perform pg_temp.evento(k1, a1, c1, pg_temp.origen('C1', 3), v_desde + interval '1 minute', v_desde);
  perform pg_temp.evento(k1, a1, c1, pg_temp.origen('C1', 4), v_desde - interval '1 minute', v_desde + interval '2 minutes');
  v_a := pg_temp.analista(pg_temp.nucleo(g1, null, v_ahora), a1);
  if pg_temp.n(v_a, 'llamadas_hoy', 'total') <> pg_temp.n(v_antes, 'llamadas_hoy', 'total') + 2
     or pg_temp.n(v_a, 'llamadas_hoy', 'sin_resultado') <> pg_temp.n(v_antes, 'llamadas_hoy', 'sin_resultado') + 2
     or pg_temp.n(v_a, 'pendientes', 'de_hoy') <> pg_temp.n(v_antes, 'pendientes', 'de_hoy') + 2
     or pg_temp.n(v_a, 'pendientes', 'anteriores') <> pg_temp.n(v_antes, 'pendientes', 'anteriores') + 1
     or pg_temp.n(v_a, 'pendientes', 'mas_antigua_dias') <> 0 then
    raise exception 'ORACULO O6: el borde del día en Lima (antes %, después %)', v_antes, v_a;
  end if;

  -- ═════ O7. Llamada de ayer resuelta hoy desde la pestaña ═════
  v_antes := v_a;
  v_e := pg_temp.evento(k1, a1, c1, pg_temp.origen('C1', 5), v_ayer + interval '10 seconds', v_ayer, 'registrado');
  v_act := pg_temp.actividad(c1, a1, v_m);
  perform pg_temp.enlace(v_e, v_act, c1, a1, 'pestana', v_m + interval '5 seconds');
  v_a := pg_temp.analista(pg_temp.nucleo(g1, null, v_ahora), a1);
  if pg_temp.n(v_a, 'resultados_hoy', 'total') <> pg_temp.n(v_antes, 'resultados_hoy', 'total') + 1
     or pg_temp.n(v_a, 'resultados_hoy', 'desde_pestana') <> 1
     or pg_temp.n(v_a, 'llamadas_hoy', 'total') <> pg_temp.n(v_antes, 'llamadas_hoy', 'total')
     or pg_temp.n(v_a, 'pendientes', 'anteriores') <> pg_temp.n(v_antes, 'pendientes', 'anteriores') then
    raise exception 'ORACULO O7: la de ayer resuelta hoy va en resultados y no en llamadas de hoy (%)', v_a;
  end if;

  -- ═════ O8. Los tres casos de A2 (a2): resultados_hoy sigue la FECHA DE LA ACTIVIDAD, no la del enlace ═════
  -- (a) intención cumplida tras medianoche: actividad 23:55 de ayer, enlace 00:03 de hoy.
  v_e := pg_temp.evento(k3, a2, c3, pg_temp.origen('C3', 1), v_desde - interval '9 minutes', v_desde - interval '10 minutes', 'registrado');
  v_act := pg_temp.actividad(c3, a2, v_desde - interval '5 minutes');
  perform pg_temp.enlace(v_e, v_act, c3, a2, 'al_colgar', v_desde + interval '3 minutes');
  -- (b) enlace manual hoy de una actividad de ayer.
  v_e := pg_temp.evento(k3, a2, c3, pg_temp.origen('C3', 2), v_ayer + interval '10 seconds', v_ayer, 'registrado');
  v_act := pg_temp.actividad(c3, a2, v_ayer + interval '8 hours');
  perform pg_temp.enlace(v_e, v_act, c3, a2, 'manual', v_m);
  v_a := pg_temp.analista(pg_temp.nucleo(g1, null, v_ahora), a2);
  if pg_temp.n(v_a, 'resultados_hoy', 'total') <> 0 or pg_temp.n(v_a, 'llamadas_hoy', 'total') <> 0 then
    raise exception 'ORACULO O8: actividades de ayer enlazadas hoy no son resultados de hoy (%)', v_a;
  end if;
  -- (c) enlace movido hoy desde una actividad de ayer (deshecha) a una de hoy → cuenta hoy, con su vía.
  v_e := pg_temp.evento(k3, a2, c3, pg_temp.origen('C3', 3), v_ayer + interval '10 seconds', v_ayer, 'registrado');
  v_act := pg_temp.actividad(c3, a2, v_ayer + interval '1 hour', true);
  v_en := pg_temp.enlace(v_e, v_act, c3, a2, 'al_colgar', v_ayer + interval '1 hour');
  v_act2 := pg_temp.actividad(c3, a2, v_m);
  update crm.llamadas_celular_enlaces set actividad_id = v_act2 where id = v_en;
  v_a := pg_temp.analista(pg_temp.nucleo(g1, null, v_ahora), a2);
  if pg_temp.n(v_a, 'resultados_hoy', 'total') <> 1 or pg_temp.n(v_a, 'resultados_hoy', 'al_colgar') <> 1
     or pg_temp.n(v_a, 'pendientes', 'deshechas_sin_corregir') <> 0 then
    raise exception 'ORACULO O8: el enlace movido a una actividad de hoy cuenta hoy, una vez (%)', v_a;
  end if;

  -- ═════ O9. Deshacer y corregir, con la distribución completa (a3, lead c8) ═════
  v_e := pg_temp.evento(k2, a3, c8, pg_temp.origen('C2', 1), v_m + interval '10 seconds', v_m, 'registrado');
  v_act := pg_temp.actividad(c8, a3, v_m + interval '20 seconds');
  v_en := pg_temp.enlace(v_e, v_act, c8, a3, 'al_colgar', v_m + interval '25 seconds');
  v_a := pg_temp.analista(pg_temp.nucleo(g1, null, v_ahora), a3);
  if pg_temp.n(v_a, 'llamadas_hoy', 'total') <> 1 or pg_temp.n(v_a, 'llamadas_hoy', 'con_resultado') <> 1
     or pg_temp.n(v_a, 'resultados_hoy', 'total') <> 1 then
    raise exception 'ORACULO O9: antes de deshacer (%)', v_a;
  end if;
  perform pg_temp.deshacer(v_act);
  v_a := pg_temp.analista(pg_temp.nucleo(g1, null, v_ahora), a3);
  if pg_temp.n(v_a, 'llamadas_hoy', 'total') <> 1 or pg_temp.n(v_a, 'llamadas_hoy', 'deshechas_sin_corregir') <> 1
     or pg_temp.n(v_a, 'llamadas_hoy', 'con_resultado') <> 0 or pg_temp.n(v_a, 'llamadas_hoy', 'sin_resultado') <> 0
     or pg_temp.n(v_a, 'pendientes', 'deshechas_sin_corregir') <> 1 or pg_temp.n(v_a, 'pendientes', 'total') <> 0
     or pg_temp.n(v_a, 'resultados_hoy', 'total') <> 0 then
    raise exception 'ORACULO O9: tras deshacer, la llamada es «deshecha sin corregir» y el resultado deja de contar (%)', v_a;
  end if;
  -- «Registrar el corregido»: el enlace se mueve a la actividad corregida.
  v_act2 := pg_temp.actividad(c8, a3, now());
  update crm.llamadas_celular_enlaces set actividad_id = v_act2 where id = v_en;
  v_a := pg_temp.analista(pg_temp.nucleo(g1, null, v_ahora), a3);
  if pg_temp.n(v_a, 'llamadas_hoy', 'total') <> 1 or pg_temp.n(v_a, 'llamadas_hoy', 'con_resultado') <> 1
     or pg_temp.n(v_a, 'llamadas_hoy', 'deshechas_sin_corregir') <> 0 or pg_temp.n(v_a, 'pendientes', 'deshechas_sin_corregir') <> 0
     or pg_temp.n(v_a, 'resultados_hoy', 'total') <> 1 then
    raise exception 'ORACULO O9: tras corregir vuelve a «con resultado», sin duplicar (%)', v_a;
  end if;
  -- Variante: deshecha y después el lead se convierte → «ya no piden resultado».
  insert into crm.leads (id, nombre_completo, telefono, etapa, vendedor_id) values (c9, 'Lead que se convierte', '+51900000009', 'nuevo', a3);
  v_e := pg_temp.evento(k2, a3, c9, pg_temp.origen('C2', 2), v_m + interval '10 seconds', v_m, 'registrado');
  v_act := pg_temp.actividad(c9, a3, v_m + interval '20 seconds');
  perform pg_temp.enlace(v_e, v_act, c9, a3, 'pestana', v_m + interval '25 seconds');
  perform pg_temp.deshacer(v_act);
  v_a := pg_temp.analista(pg_temp.nucleo(g1, null, v_ahora), a3);
  if pg_temp.n(v_a, 'llamadas_hoy', 'total') <> 2 or pg_temp.n(v_a, 'llamadas_hoy', 'deshechas_sin_corregir') <> 1
     or pg_temp.n(v_a, 'pendientes', 'deshechas_sin_corregir') <> 1 then
    raise exception 'ORACULO O9: segunda deshecha (%)', v_a;
  end if;
  update crm.leads set etapa = 'convertido' where id = c9;
  v_a := pg_temp.analista(pg_temp.nucleo(g1, null, v_ahora), a3);
  if pg_temp.n(v_a, 'llamadas_hoy', 'total') <> 2 or pg_temp.n(v_a, 'llamadas_hoy', 'cerradas_despues') <> 1
     or pg_temp.n(v_a, 'llamadas_hoy', 'deshechas_sin_corregir') <> 0 or pg_temp.n(v_a, 'pendientes', 'deshechas_sin_corregir') <> 0 then
    raise exception 'ORACULO O9: deshecha de un lead convertido → cerradas después (%)', v_a;
  end if;
  -- Variante: deshecha de hace 40 días → sigue en pendientes.deshechas_sin_corregir (la purga no la toca).
  insert into crm.leads (id, nombre_completo, telefono, etapa, vendedor_id) values (c40, 'Lead solo historial antiguo', '+51900000040', 'nuevo', a3);
  v_e := pg_temp.evento(k2, a3, c40, pg_temp.origen('C2', 3), v_ahora - interval '40 days', v_ahora - interval '40 days', 'registrado');
  v_act := pg_temp.actividad(c40, a3, v_ahora - interval '40 days' + interval '1 minute', true);
  perform pg_temp.enlace(v_e, v_act, c40, a3, 'al_colgar', v_ahora - interval '40 days' + interval '2 minutes');
  v_a := pg_temp.analista(pg_temp.nucleo(g1, null, v_ahora), a3);
  if pg_temp.n(v_a, 'pendientes', 'deshechas_sin_corregir') <> 1 or pg_temp.n(v_a, 'llamadas_hoy', 'total') <> 2
     or pg_temp.n(v_a, 'pendientes', 'total') <> 0 then
    raise exception 'ORACULO O9: la deshecha de hace 40 días cuenta entre las pendientes sin tope (%)', v_a;
  end if;

  -- ═════ O10. Por revisar: una ambigua no toca «sin resultado»; una reutilizable identificada sí entra en la cohorte ═════
  v_antes := pg_temp.analista(pg_temp.nucleo(g1, null, v_ahora), a1);
  perform pg_temp.evento(k1, a1, null, pg_temp.origen('C1', 6), v_m, v_m, 'por_revisar', 'ambiguo');
  v_a := pg_temp.analista(pg_temp.nucleo(g1, null, v_ahora), a1);
  if pg_temp.n(v_a, 'por_revisar') <> pg_temp.n(v_antes, 'por_revisar') + 1
     or pg_temp.n(v_a, 'llamadas_hoy', 'total') <> pg_temp.n(v_antes, 'llamadas_hoy', 'total')
     or pg_temp.n(v_a, 'llamadas_hoy', 'sin_resultado') <> pg_temp.n(v_antes, 'llamadas_hoy', 'sin_resultado') then
    raise exception 'ORACULO O10: la ambigua suma por revisar y no toca la cohorte (%)', v_a;
  end if;
  perform pg_temp.evento(k1, a1, c6, pg_temp.origen('C1', 7), v_m, v_m, 'por_revisar');
  v_a := pg_temp.analista(pg_temp.nucleo(g1, null, v_ahora), a1);
  if pg_temp.n(v_a, 'por_revisar') <> pg_temp.n(v_antes, 'por_revisar') + 2
     or pg_temp.n(v_a, 'llamadas_hoy', 'total') <> pg_temp.n(v_antes, 'llamadas_hoy', 'total') + 1
     or pg_temp.n(v_a, 'llamadas_hoy', 'por_revisar') <> 1
     or pg_temp.n(v_a, 'llamadas_hoy', 'sin_resultado') <> pg_temp.n(v_antes, 'llamadas_hoy', 'sin_resultado') then
    raise exception 'ORACULO O10: la reutilizable identificada entra en la cohorte como por revisar (%)', v_a;
  end if;

  -- ═════ O11. Lead de baja (A4) y lead convertido después (A5), sobre a2 ═════
  perform pg_temp.evento(k3, a2, c3, pg_temp.origen('C3', 4), v_m + interval '10 seconds', v_m);
  v_a := pg_temp.analista(pg_temp.nucleo(g1, null, v_ahora), a2);
  if pg_temp.n(v_a, 'llamadas_hoy', 'total') <> 1 or pg_temp.n(v_a, 'llamadas_hoy', 'sin_resultado') <> 1
     or pg_temp.n(v_a, 'pendientes', 'total') <> 1 or pg_temp.n(v_a, 'resultados_hoy', 'total') <> 1 then
    raise exception 'ORACULO O11: antes de la baja (%)', v_a;
  end if;
  update crm.leads set activo = false where id = c3;
  v_a := pg_temp.analista(pg_temp.nucleo(g1, null, v_ahora), a2);
  if pg_temp.n(v_a, 'llamadas_hoy', 'total') <> 0 or pg_temp.n(v_a, 'pendientes', 'total') <> 0
     or pg_temp.n(v_a, 'resultados_hoy', 'total') <> 0 or pg_temp.n(v_a, 'pendientes', 'deshechas_sin_corregir') <> 0 then
    raise exception 'ORACULO O11: el lead de baja debía desaparecer de todas las cubetas (%)', v_a;
  end if;
  update crm.leads set activo = true, etapa = 'convertido' where id = c3;
  v_a := pg_temp.analista(pg_temp.nucleo(g1, null, v_ahora), a2);
  if pg_temp.n(v_a, 'llamadas_hoy', 'total') <> 1 or pg_temp.n(v_a, 'llamadas_hoy', 'cerradas_despues') <> 1
     or pg_temp.n(v_a, 'llamadas_hoy', 'sin_resultado') <> 0 or pg_temp.n(v_a, 'pendientes', 'total') <> 0
     or pg_temp.n(v_a, 'resultados_hoy', 'total') <> 1 then
    raise exception 'ORACULO O11: el lead convertido pasa de sin resultado a cerradas después y conserva su resultado (%)', v_a;
  end if;
  update crm.leads set etapa = 'contactado' where id = c3;

  -- ═════ O12. Entrante insertada a mano: no cuenta en nada; requiere_devolucion = 0 siempre ═════
  v_antes := pg_temp.nucleo(g1, null, v_ahora);
  perform pg_temp.evento(k1, a1, c1, pg_temp.origen('C1', 8), v_m, v_m, 'requiere_devolucion', 'identificado', 'entrante');
  perform pg_temp.evento(k1, a1, c1, pg_temp.origen('C1', 9), v_m, v_m, 'por_revisar', 'identificado', 'desconocida');
  v_g := pg_temp.nucleo(g1, null, v_ahora);
  if (v_g - 'generado_en') <> (v_antes - 'generado_en') then
    raise exception 'ORACULO O12: una entrante o una dirección desconocida cambió las cifras';
  end if;
  if pg_temp.n(v_g, 'totales', 'llamadas_hoy', 'requiere_devolucion') <> 0
     or exists (select 1 from jsonb_array_elements(v_g -> 'analistas') a where pg_temp.n(a, 'llamadas_hoy', 'requiere_devolucion') <> 0) then
    raise exception 'ORACULO O12: requiere_devolucion debía ser 0 (%)', v_g;
  end if;

  -- ═════ O13. Latidos con los bordes del umbral, y «sin dato» (D1) ═════
  -- vn: vendedor de b2 con C4 sin latido hace 8 h y 0 llamadas → sin dato; vs: vendedor de b2 sin celular → sin dato.
  insert into public.perfiles (id, nombre_completo, rol, activo) values (vn, 'Vendedor Nuevo', 'comercial', true), (vs, 'Vendedor Sin Celular', 'comercial', true);
  insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo) values (vn, 'vendedor', b2, true), (vs, 'vendedor', b2, true);
  perform pg_temp.como(g1); k4 := (crm.asignar_celular('C4', vn) ->> 'asignacion_id')::uuid; perform pg_temp.yo();
  insert into private.celulares_estado (asignacion_id, ultimo_latido_en, latido_celular_en, version_macro, eventos_en_cola)
    values (k4, now() - interval '8 hours', now() - interval '8 hours' + interval '30 seconds', 'llamadas-v3', 5);
  v_g := pg_temp.nucleo(g1, null, v_ahora);
  v_a := pg_temp.analista(v_g, vn);
  if (v_a ->> 'sin_dato')::boolean is not true or jsonb_array_length(v_a -> 'celulares') <> 1
     or v_a -> 'celulares' -> 0 ->> 'estado_latido' is distinct from 'sin_latido'
     or pg_temp.n(v_a -> 'celulares' -> 0, 'horas_sin_latido') <> 8 or pg_temp.n(v_a -> 'celulares' -> 0, 'eventos_en_cola') <> 5
     or (v_a -> 'celulares' -> 0 ->> 'reloj_desfasado')::boolean is not false
     or v_a -> 'celulares' -> 0 ->> 'version_macro' is distinct from 'llamadas-v3' then
    raise exception 'ORACULO O13: C4 sin latido hace 8 h, 0 llamadas → sin dato (%)', v_a;
  end if;
  v_a := pg_temp.analista(v_g, vs);
  if (v_a ->> 'sin_dato')::boolean is not true or v_a -> 'celulares' <> '[]'::jsonb then
    raise exception 'ORACULO O13: sin celular vigente → sin dato y celulares vacíos (%)', v_a;
  end if;
  v_eq := pg_temp.equipo(v_g, b2);
  if pg_temp.n(v_eq, 'analistas') <> 3 or pg_temp.n(v_eq, 'analistas_sin_dato') <> 2 or pg_temp.n(v_eq, 'celulares_vigentes') <> 2
     or pg_temp.n(v_eq, 'celulares_sin_latido') <> 2 or pg_temp.n(v_g, 'totales', 'celulares_vigentes') <> 4
     or pg_temp.n(v_g, 'totales', 'celulares_sin_latido') <> 3 or pg_temp.n(v_g, 'totales', 'analistas_sin_dato') <> 2 then
    raise exception 'ORACULO O13: cuentas de celulares y sin dato del equipo b2 y los totales (%)', v_g;
  end if;
  -- a2 tiene C3 «nunca» y una llamada de hoy → con dato (y C3 cuenta como sin latido).
  v_a := pg_temp.analista(v_g, a2);
  if (v_a ->> 'sin_dato')::boolean is not false or v_a -> 'celulares' -> 0 ->> 'estado_latido' is distinct from 'nunca'
     or v_a -> 'celulares' -> 0 -> 'horas_sin_latido' <> 'null'::jsonb then
    raise exception 'ORACULO O13: C3 nunca habló y a2 sí tiene dato (%)', v_a;
  end if;
  -- Bordes del umbral sobre C4 (0 llamadas): 6 h 30 y 7 h 00 exactas → al día (y ya no es «sin dato»); 7 h 00 min 01 s → sin latido.
  update private.celulares_estado set ultimo_latido_en = now() - interval '6 hours 30 minutes', latido_celular_en = now() - interval '6 hours 30 minutes' where asignacion_id = k4;
  v_a := pg_temp.analista(pg_temp.nucleo(g1, null, v_ahora), vn);
  if v_a -> 'celulares' -> 0 ->> 'estado_latido' is distinct from 'al_dia' or (v_a ->> 'sin_dato')::boolean is not false
     or pg_temp.n(v_a, 'llamadas_hoy', 'total') <> 0 then
    raise exception 'ORACULO O13: latido hace 6 h 30 → al día, y 0 llamadas con latido no es «sin dato» (%)', v_a;
  end if;
  update private.celulares_estado set ultimo_latido_en = now() - interval '7 hours', latido_celular_en = now() - interval '7 hours' where asignacion_id = k4;
  v_a := pg_temp.analista(pg_temp.nucleo(g1, null, v_ahora), vn);
  if v_a -> 'celulares' -> 0 ->> 'estado_latido' is distinct from 'al_dia' or (v_a ->> 'sin_dato')::boolean is not false then
    raise exception 'ORACULO O13: latido hace 7 h exactas → todavía al día (%)', v_a;
  end if;
  update private.celulares_estado set ultimo_latido_en = now() - interval '7 hours 1 second', latido_celular_en = now() - interval '7 hours 1 second' where asignacion_id = k4;
  v_a := pg_temp.analista(pg_temp.nucleo(g1, null, v_ahora), vn);
  if v_a -> 'celulares' -> 0 ->> 'estado_latido' is distinct from 'sin_latido' or (v_a ->> 'sin_dato')::boolean is not true then
    raise exception 'ORACULO O13: latido hace 7 h 1 s → sin latido y sin dato (%)', v_a;
  end if;
  -- su_celular (A7): el supervisor b2 recibe su propio celular aparte y no se suma al equipo.
  perform pg_temp.como(g1); k5 := (crm.asignar_celular('C5', b2) ->> 'asignacion_id')::uuid; perform pg_temp.yo();
  v_x := pg_temp.nucleo(b2, null, v_ahora);
  if jsonb_array_length(v_x -> 'su_celular') <> 1 or v_x -> 'su_celular' -> 0 ->> 'etiqueta' is distinct from 'C5'
     or pg_temp.n(v_x, 'totales', 'celulares_vigentes') <> 2
     or exists (select 1 from jsonb_array_elements(v_x -> 'analistas') a where (a ->> 'analista_id')::uuid = b2) then
    raise exception 'ORACULO O13/A7: el celular del supervisor va aparte (%)', v_x;
  end if;
  perform pg_temp.como(g1); perform crm.cerrar_asignacion_celular(k5, 'reemplazo'); perform pg_temp.yo();

  -- ═════ O14. Privacidad: ninguna clave ni valor delator, a cualquier profundidad; ningún porcentaje ═════
  v_g := pg_temp.puerta(g1); v_b := pg_temp.puerta(b2);
  if exists (
    select 1 from (select * from pg_temp.hojas(v_g) union all select * from pg_temp.hojas(v_b)) h
    where h.clave in ('numero', 'numero_canonico', 'telefono', 'lead_id', 'evento_id', 'evento_origen_id', 'asignacion_id',
                      'credencial', 'credencial_hash', 'ultimo_latido_en', 'latido_celular_en', 'ultimo_envio_en', 'vigente_desde',
                      'analista_nombre', 'lead_nombre', 'nombre_completo')
       or h.clave ~* 'porcentaje|pct|ratio'
       or h.valor ~ '^\+?[0-9]{7,}$'
       or h.valor ~* 'lead ') then
    raise exception 'ORACULO O14: el jsonb delata algo (%)', (select jsonb_agg(h) from (select * from pg_temp.hojas(v_g) union all select * from pg_temp.hojas(v_b)) h
                                                               where h.clave in ('numero', 'lead_id', 'evento_id', 'ultimo_latido_en') or h.valor ~ '^\+?[0-9]{7,}$' or h.valor ~* 'lead ');
  end if;

  -- ═════ O16. Reloj corrido (D2): 20 min por delante → el momento es recibido_en ═════
  -- Recibida 23:50 de ayer con ocurrio_en 00:10 de hoy: por la hora del celular sería de hoy; por D2 es de ayer.
  v_antes := pg_temp.analista(pg_temp.nucleo(g1, null, v_ahora), a1);
  perform pg_temp.evento(k1, a1, c1, pg_temp.origen('C1', 10), v_desde - interval '10 minutes', v_desde + interval '10 minutes');
  v_a := pg_temp.analista(pg_temp.nucleo(g1, null, v_ahora), a1);
  if pg_temp.n(v_a, 'llamadas_hoy', 'total') <> pg_temp.n(v_antes, 'llamadas_hoy', 'total')
     or pg_temp.n(v_a, 'pendientes', 'anteriores') <> pg_temp.n(v_antes, 'pendientes', 'anteriores') + 1
     or pg_temp.n(v_a, 'pendientes', 'de_hoy') <> pg_temp.n(v_antes, 'pendientes', 'de_hoy') then
    raise exception 'ORACULO O16: con el reloj corrido manda recibido_en (antes %, después %)', v_antes, v_a;
  end if;
  -- Retención (D5): una pendiente sin enlace de hace 40 días ya no existe para la purga; tampoco para la foto de ahora.
  v_antes := v_a;
  perform pg_temp.evento(k1, a1, c1, pg_temp.origen('C1', 11), v_ahora - interval '40 days', v_ahora - interval '40 days');
  v_a := pg_temp.analista(pg_temp.nucleo(g1, null, v_ahora), a1);
  if pg_temp.cifras(v_a) <> pg_temp.cifras(v_antes) then
    raise exception 'ORACULO O16/D5: una pendiente fuera de la retención no cuenta (antes %, después %)', v_antes, v_a;
  end if;

  -- ═════ O17. Supervisores anidados (D4): S2 bajo b1, V bajo S2; gerencia, b1 y S2 ven las mismas cifras de V ═════
  insert into public.perfiles (id, nombre_completo, rol, activo) values (s2, 'Supervisor Anidado', 'comercial', true), (vv, 'Vendedor Anidado', 'comercial', true);
  insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo) values (s2, 'supervisor', b1, true), (vv, 'vendedor', s2, true);
  perform pg_temp.como(g1); k5 := (crm.asignar_celular('C6', vv) ->> 'asignacion_id')::uuid; perform pg_temp.yo();
  perform pg_temp.evento(k5, vv, c1, pg_temp.origen('C6', 1), v_m + interval '10 seconds', v_m);
  v_g := pg_temp.nucleo(g1, null, v_ahora); v_b := pg_temp.nucleo(b1, null, v_ahora); v_x := pg_temp.nucleo(s2, null, v_ahora);
  if pg_temp.analista(v_g, vv) is null or pg_temp.analista(v_b, vv) is null or pg_temp.analista(v_x, vv) is null then
    raise exception 'ORACULO O17: V debía aparecer para gerencia, b1 y S2';
  end if;
  if pg_temp.cifras(pg_temp.analista(v_g, vv)) <> pg_temp.cifras(pg_temp.analista(v_b, vv))
     or pg_temp.cifras(pg_temp.analista(v_g, vv)) <> pg_temp.cifras(pg_temp.analista(v_x, vv))
     or pg_temp.n(pg_temp.analista(v_x, vv), 'llamadas_hoy', 'total') <> 1 then
    raise exception 'ORACULO O17: cifras distintas de V según quién pregunta (g %, b1 %, s2 %)', pg_temp.analista(v_g, vv), pg_temp.analista(v_b, vv), pg_temp.analista(v_x, vv);
  end if;
  -- La composición sí cambia: para gerencia V cuelga de S2 (equipo propio); para b1 está en su único equipo; S2 solo ve a V.
  if (pg_temp.analista(v_g, vv) ->> 'supervisor_id')::uuid <> s2 or pg_temp.n(pg_temp.equipo(v_g, s2), 'analistas') <> 1
     or pg_temp.n(pg_temp.equipo(v_g, b1), 'analistas') <> 2
     or pg_temp.ids(v_b) <> array[a1, a2, vv] or pg_temp.n(pg_temp.equipo(v_b, b1), 'analistas') <> 3
     or pg_temp.ids(v_x) <> array[vv] or jsonb_array_length(v_x -> 'equipos') <> 1 then
    raise exception 'ORACULO O17: composición de equipos (g %, b1 %, s2 %)', v_g -> 'equipos', v_b -> 'equipos', v_x -> 'equipos';
  end if;

  -- ═════ O15. Cierre de cubetas: cada total es la suma de sus partes; equipos y totales, sumas de sus analistas ═════
  foreach v_a in array array[pg_temp.nucleo(g1, null, v_ahora), pg_temp.nucleo(b1, null, v_ahora), pg_temp.nucleo(b2, null, v_ahora)] loop
    if exists (
      select 1 from jsonb_array_elements(v_a -> 'analistas') x
      where pg_temp.n(x, 'llamadas_hoy', 'total') <> pg_temp.n(x, 'llamadas_hoy', 'con_resultado') + pg_temp.n(x, 'llamadas_hoy', 'deshechas_sin_corregir')
            + pg_temp.n(x, 'llamadas_hoy', 'sin_resultado') + pg_temp.n(x, 'llamadas_hoy', 'cerradas_despues')
            + pg_temp.n(x, 'llamadas_hoy', 'descartadas') + pg_temp.n(x, 'llamadas_hoy', 'por_revisar')
         or pg_temp.n(x, 'resultados_hoy', 'total') <> pg_temp.n(x, 'resultados_hoy', 'al_colgar') + pg_temp.n(x, 'resultados_hoy', 'desde_pestana') + pg_temp.n(x, 'resultados_hoy', 'a_mano')
         or pg_temp.n(x, 'pendientes', 'total') <> pg_temp.n(x, 'pendientes', 'de_hoy') + pg_temp.n(x, 'pendientes', 'anteriores')) then
      raise exception 'ORACULO O15: las cubetas de un analista no cierran (%)', v_a -> 'analistas';
    end if;
    foreach v_ruta slice 1 in array array[
      ['llamadas_hoy', 'total'], ['llamadas_hoy', 'con_resultado'], ['llamadas_hoy', 'deshechas_sin_corregir'],
      ['llamadas_hoy', 'sin_resultado'], ['llamadas_hoy', 'cerradas_despues'], ['llamadas_hoy', 'descartadas'],
      ['llamadas_hoy', 'por_revisar'], ['llamadas_hoy', 'requiere_devolucion'],
      ['resultados_hoy', 'total'], ['resultados_hoy', 'al_colgar'], ['resultados_hoy', 'desde_pestana'], ['resultados_hoy', 'a_mano'],
      ['pendientes', 'total'], ['pendientes', 'de_hoy'], ['pendientes', 'anteriores'], ['pendientes', 'deshechas_sin_corregir'],
      ['por_revisar', null]] loop
      v_ruta := array_remove(v_ruta, null);
      if pg_temp.n(v_a -> 'totales', variadic v_ruta) <> pg_temp.suma(v_a -> 'analistas', variadic v_ruta)
         or exists (
           select 1 from jsonb_array_elements(v_a -> 'equipos') e
           where pg_temp.n(e, variadic v_ruta) <> (select coalesce(sum((x #>> v_ruta)::integer), 0) from jsonb_array_elements(v_a -> 'analistas') x
                                                   where x ->> 'supervisor_id' is not distinct from e ->> 'supervisor_id')) then
        raise exception 'ORACULO O15: % no es la suma de los analistas (%)', v_ruta, v_a;
      end if;
    end loop;
    -- La antigüedad del equipo es la de su pendiente más antigua; los celulares y «sin dato», conteos de sus analistas.
    if exists (
      select 1 from jsonb_array_elements(v_a -> 'equipos') e
      where pg_temp.n(e, 'pendientes', 'mas_antigua_dias') is distinct from (
              select max(pg_temp.n(x, 'pendientes', 'mas_antigua_dias')) from jsonb_array_elements(v_a -> 'analistas') x
              where x ->> 'supervisor_id' is not distinct from e ->> 'supervisor_id')
         or pg_temp.n(e, 'celulares_vigentes') <> (select coalesce(sum(jsonb_array_length(x -> 'celulares')), 0) from jsonb_array_elements(v_a -> 'analistas') x
                                                    where x ->> 'supervisor_id' is not distinct from e ->> 'supervisor_id')
         or pg_temp.n(e, 'analistas_sin_dato') <> (select count(*) from jsonb_array_elements(v_a -> 'analistas') x
                                                   where x ->> 'supervisor_id' is not distinct from e ->> 'supervisor_id' and (x ->> 'sin_dato')::boolean)
         or pg_temp.n(e, 'analistas') <> (select count(*) from jsonb_array_elements(v_a -> 'analistas') x
                                          where x ->> 'supervisor_id' is not distinct from e ->> 'supervisor_id')) then
      raise exception 'ORACULO O15: antigüedad, celulares o «sin dato» de un equipo (%)', v_a -> 'equipos';
    end if;
    if pg_temp.n(v_a, 'totales', 'celulares_sin_latido') <> (
         select count(*) from jsonb_array_elements(v_a -> 'analistas') x, jsonb_array_elements(x -> 'celulares') c where c ->> 'estado_latido' <> 'al_dia')
       or pg_temp.n(v_a, 'totales', 'analistas_sin_dato') <> pg_temp.suma(v_a -> 'equipos', 'analistas_sin_dato')
       or pg_temp.n(v_a, 'totales', 'celulares_vigentes') <> pg_temp.suma(v_a -> 'equipos', 'celulares_vigentes') then
      raise exception 'ORACULO O15: totales de celulares o «sin dato» (%)', v_a -> 'totales';
    end if;
  end loop;

  if v_ok <> 9 then raise exception 'ORACULO: % de 9 rechazos esperados', v_ok; end if;
  raise notice 'ORACULO OPERACION HOY OK: roles y p_supervisor_id, aislamiento y claves de equipo, ingesta y registro al colgar, borde del día en Lima, resultados por la fecha de la actividad, deshacer y corregir, por revisar, lead de baja y convertido, entrantes fuera, latidos y «sin dato», privacidad, cierre de cubetas, reloj corrido y supervisores anidados';
end;
$oraculo$;

rollback;
