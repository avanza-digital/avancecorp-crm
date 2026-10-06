-- Oráculo de la undécima (20261006150254, salud de los celulares sin la hora exacta del latido) sobre el banco REDUCIDO
-- de supabase/tests/llamadas-celular/base.sql. Se corre como dueño después de las diez y la undécima; todo en una
-- transacción que termina en ROLLBACK. Cubre: estado del latido (al día, sin latido pasadas 7 h, nunca), horas enteras,
-- reloj desfasado, que no salgan las horas exactas, el ámbito (gerencia todos; supervisión su equipo) y los roles.
-- Equipo del banco: b1 supervisa a a1 y a2; b2 supervisa a a3; g1 es gerencia.
-- No sustituye el gate test-rls.mjs contra un banco con el esquema de producción.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';

create function pg_temp.salud(p_actor uuid)
returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claim.sub', p_actor::text, true);
  execute 'set local role authenticated';
  v := crm.celulares_salud_fn();
  execute 'set local role none';
  perform set_config('request.jwt.claim.sub', '', true);
  return v;
end $$;
create function pg_temp.de(p_salud jsonb, p_etiqueta text)
returns jsonb language sql immutable as $$
  select f from jsonb_array_elements(p_salud) f where f ->> 'etiqueta' = p_etiqueta
$$;
create function pg_temp.etiquetas(p_salud jsonb)
returns text[] language sql immutable as $$
  select coalesce(array_agg(f ->> 'etiqueta' order by f ->> 'etiqueta'), '{}') from jsonb_array_elements(p_salud) f
$$;

do $oraculo$
declare
  a1 constant uuid := '00000000-0000-0000-0000-0000000000a1';
  a2 constant uuid := '00000000-0000-0000-0000-0000000000a2';
  a3 constant uuid := '00000000-0000-0000-0000-0000000000a3';
  b1 constant uuid := '00000000-0000-0000-0000-0000000000b1';
  b2 constant uuid := '00000000-0000-0000-0000-0000000000b2';
  g1 constant uuid := '00000000-0000-0000-0000-0000000000f1';
  c1 uuid; c2 uuid; c3 uuid;
  v_s jsonb;
  v_f jsonb;
  v_ok integer := 0;
begin
  -- ═════ Preparación: C1 de a1 (latido hace 1 h 30, reloj corrido 10 min), C2 de a3 (latido hace 8 h), C3 de a2 (nunca) ═════
  perform set_config('request.jwt.claim.sub', g1::text, true); execute 'set local role authenticated';
  c1 := (crm.asignar_celular('C1', a1) ->> 'asignacion_id')::uuid;
  c2 := (crm.asignar_celular('C2', a3) ->> 'asignacion_id')::uuid;
  c3 := (crm.asignar_celular('C3', a2) ->> 'asignacion_id')::uuid;
  execute 'set local role none'; perform set_config('request.jwt.claim.sub', '', true);
  insert into private.celulares_estado (asignacion_id, ultimo_latido_en, latido_celular_en, version_macro, eventos_en_cola) values
    (c1, now() - interval '90 minutes', now() - interval '80 minutes', 'llamadas-v2', 0),
    (c2, now() - interval '8 hours', now() - interval '8 hours' + interval '30 seconds', 'llamadas-v2', 3);

  -- ═════ S. Estado, horas enteras y reloj ═════
  v_s := pg_temp.salud(g1);
  if pg_temp.etiquetas(v_s) is distinct from array['C1', 'C2', 'C3'] then
    raise exception 'ORACULO S1: gerencia debía ver los tres celulares (%)', v_s;
  end if;
  v_f := pg_temp.de(v_s, 'C1');
  if v_f ->> 'estado_latido' is distinct from 'al_dia' or (v_f ->> 'horas_sin_latido')::integer is distinct from 1
     or (v_f ->> 'reloj_desfasado')::boolean is not true or v_f ->> 'version_macro' is distinct from 'llamadas-v2' then
    raise exception 'ORACULO S2: C1 debía estar al día, hace 1 h y con el reloj corrido (%)', v_f;
  end if;
  v_f := pg_temp.de(v_s, 'C2');
  if v_f ->> 'estado_latido' is distinct from 'sin_latido' or (v_f ->> 'horas_sin_latido')::integer is distinct from 8
     or (v_f ->> 'reloj_desfasado')::boolean is not false or (v_f ->> 'eventos_en_cola')::integer is distinct from 3 then
    raise exception 'ORACULO S3: C2 debía estar sin latido hace 8 h, con el reloj bien y 3 en cola (%)', v_f;
  end if;
  v_f := pg_temp.de(v_s, 'C3');
  if v_f ->> 'estado_latido' is distinct from 'nunca' or v_f -> 'horas_sin_latido' <> 'null'::jsonb
     or (v_f ->> 'reloj_desfasado')::boolean is not false then
    raise exception 'ORACULO S4: C3 nunca habló (%)', v_f;
  end if;

  -- Un latido sellado un instante por delante de now() (el reloj real corre dentro de la transacción): 0 horas, no -1.
  update private.celulares_estado set ultimo_latido_en = now() + interval '2 seconds', latido_celular_en = now() + interval '2 seconds'
   where asignacion_id = c2;
  v_f := pg_temp.de(pg_temp.salud(g1), 'C2');
  if v_f ->> 'estado_latido' is distinct from 'al_dia' or (v_f ->> 'horas_sin_latido')::integer is distinct from 0
     or (v_f ->> 'reloj_desfasado')::boolean is not false then
    raise exception 'ORACULO S5: un latido de recién debía dar al día y 0 horas (%)', v_f;
  end if;

  -- ═════ H. Ninguna hora exacta sale ═════
  if exists (select 1 from jsonb_array_elements(v_s) f where f ? 'ultimo_latido_en' or f ? 'latido_celular_en' or f ? 'ultimo_envio_en') then
    raise exception 'ORACULO H1: la salud devolvió una hora exacta (%)', v_s;
  end if;

  -- ═════ A. Ámbito y roles ═════
  if pg_temp.etiquetas(pg_temp.salud(b1)) is distinct from array['C1', 'C3']
     or pg_temp.etiquetas(pg_temp.salud(b2)) is distinct from array['C2'] then
    raise exception 'ORACULO A1: cada supervisión debía ver solo los celulares de su equipo';
  end if;
  begin
    perform pg_temp.salud(a1);
    raise exception 'ORACULO A2: un analista leyó la salud';
  exception when insufficient_privilege then v_ok := v_ok + 1;
  end;

  if v_ok <> 1 then raise exception 'ORACULO: % de 1 rechazos esperados', v_ok; end if;
  raise notice 'ORACULO SALUD SIN HORA OK: estado del latido (al día, sin latido pasadas 7 h, nunca), horas enteras, reloj desfasado, sin horas exactas, ámbito por equipo y roles';
end;
$oraculo$;

rollback;
