-- B11 · Paridad ANTES / DESPUÉS de las salidas de conversión (SOLO LECTURA: termina en ROLLBACK).
--
-- Se corre igual antes y después de aplicar 20261006042144 (banco, rama con datos y, si Miguel quiere, producción) y se
-- comparan las dos listas: con 0 cierres de contactos de base, TODA salida debe ser idéntica. La única diferencia admitida
-- es la clave nueva `base_cargada` del Divisor de coordinación, que se quita antes de la huella y se informa aparte (su
-- suma debe ser 0 donde no hay cierres de base).
-- Actúa como Gerencia (el primer perfil con rol gerencia), con claims locales a la transacción; la alarma, que solo admite
-- el rol de servicio o una sesión de operador SIN claims, se consulta antes de ponerlos. Un mes en curso se mide hasta hoy.
-- Uso: psql … -X -At -F' | ' -f supabase/scripts/base-gestion/b11-paridad.sql > antes.txt   (y luego > despues.txt; diff)

begin;
set transaction isolation level repeatable read;
set local statement_timeout = '300s';
set local search_path = '';

-- Quita la hora de la consulta (now() / statement_timestamp(): generado_en, madura_hasta, seguimiento_hasta…), que cambia
-- en cada corrida, y la clave nueva base_cargada.
create function pg_temp.b11_limpio(p jsonb) returns text language sql stable as $$
  select pg_catalog.regexp_replace(pg_catalog.regexp_replace(pg_catalog.replace(pg_catalog.replace(p::text,
    pg_catalog.to_jsonb(pg_catalog.now())::text, '"<ahora>"'),
    pg_catalog.to_jsonb(pg_catalog.statement_timestamp())::text, '"<ahora>"'),
    ', "base_cargada": (null|[0-9]+)', '', 'g'),
    '"base_cargada": (null|[0-9]+), ', '', 'g')
$$;

create function pg_temp.b11_base(p jsonb) returns text language sql immutable as $$
  select coalesce(sum((m[1])::int)::text, 'sin clave') || ' (' || count(*)::text || ' claves, '
         || count(*) filter (where m[1] is null)::text || ' null)'
    from pg_catalog.regexp_matches(p::text, '"base_cargada": (?:null|([0-9]+))', 'g') as m
$$;

create temporary table b11_salidas (etiqueta text primary key, huella text, nota text) on commit drop;

do $paridad$
declare
  v_ger uuid;
  v_mes date;
  v_ini timestamptz;
  v_fin timestamptz;
  v_hasta date;
  v_j jsonb;
  v_t text;
  v_corte constant timestamptz := '2026-10-05 23:00:00-05';
begin
  foreach v_mes in array array['2026-08-01'::date, '2026-09-01'::date, '2026-10-01'::date] loop
    begin
      v_j := pg_catalog.to_jsonb(crm.alarma_conversion_fn(v_mes));
      insert into b11_salidas values ('alarma ' || v_mes, pg_catalog.md5(pg_temp.b11_limpio(v_j)), null);
    exception when others then insert into b11_salidas values ('alarma ' || v_mes, 'ERROR', sqlerrm); end;
  end loop;

  select e.perfil_id into v_ger from crm.equipo e where private.rol_crm(e.perfil_id) = 'gerencia' order by e.perfil_id limit 1;
  if v_ger is null then raise exception 'NOT RUN: no hay perfil de gerencia'; end if;
  perform pg_catalog.set_config('request.jwt.claims', pg_catalog.json_build_object('sub', v_ger, 'role', 'authenticated')::text, true);
  perform pg_catalog.set_config('request.jwt.claim.sub', v_ger::text, true);

  foreach v_mes in array array['2026-08-01'::date, '2026-09-01'::date, '2026-10-01'::date] loop
    v_hasta := least((v_mes + interval '1 month' - interval '1 day')::date, (pg_catalog.now() at time zone 'America/Lima')::date);
    v_ini := v_mes::timestamp at time zone 'America/Lima';
    v_fin := (v_mes + interval '1 month')::timestamp at time zone 'America/Lima';

    begin
      v_j := crm.conversion_divisor_coordinacion_fn(v_mes, null, null);
      insert into b11_salidas values ('coordinacion ' || v_mes, pg_catalog.md5(pg_temp.b11_limpio(v_j)), 'base_cargada: ' || pg_temp.b11_base(v_j));
    exception when others then insert into b11_salidas values ('coordinacion ' || v_mes, 'ERROR', sqlerrm); end;

    begin
      v_j := crm.conversion_mensual_sin_cartera_fn(v_mes);
      insert into b11_salidas values ('mensual_sin_cartera ' || v_mes, pg_catalog.md5(pg_temp.b11_limpio(v_j)), null);
    exception when others then insert into b11_salidas values ('mensual_sin_cartera ' || v_mes, 'ERROR', sqlerrm); end;

    begin
      v_j := crm.metricas_conversiones_equipo_fn(v_mes, v_hasta);
      insert into b11_salidas values ('equipo ' || v_mes, pg_catalog.md5(pg_temp.b11_limpio(v_j)), null);
    exception when others then insert into b11_salidas values ('equipo ' || v_mes, 'ERROR', sqlerrm); end;

    begin
      v_j := private.metricas_conversiones_implementacion(v_mes, v_hasta, null);
      insert into b11_salidas values ('implementacion ' || v_mes, pg_catalog.md5(pg_temp.b11_limpio(v_j)), null);
    exception when others then insert into b11_salidas values ('implementacion ' || v_mes, 'ERROR', sqlerrm); end;

    begin
      v_j := private.metricas_distribucion_leads_v3_core(v_mes, v_hasta, v_corte);
      insert into b11_salidas values ('distribucion_v3 ' || v_mes, pg_catalog.md5(pg_temp.b11_limpio(v_j)), null);
    exception when others then insert into b11_salidas values ('distribucion_v3 ' || v_mes, 'ERROR', sqlerrm); end;

    begin
      select pg_catalog.md5(coalesce(pg_catalog.string_agg(t::text, E'\n' order by t::text), ''))
        into v_t from private.conversion_mensual_por_vendedor(v_ini, v_fin, true, null::uuid[], private.peso_referido_conversion(v_mes)) t;
      insert into b11_salidas values ('mensual_por_vendedor ' || v_mes, v_t, null);
    exception when others then insert into b11_salidas values ('mensual_por_vendedor ' || v_mes, 'ERROR', sqlerrm); end;

    begin
      -- Proyección a las columnas de antes de B11 (la nueva se informa en la coordinación).
      select pg_catalog.md5(coalesce(pg_catalog.string_agg(pg_catalog.concat_ws('|', f.analista_id, f.nombre, f.supervisor_id,
               f.supervisor_nombre, f.en_nucleo, f.divisor, f.divisor_formulario, f.divisor_landing, f.numerador, f.conversion_pct,
               f.numerador_bruto, f.ajuste_pendiente, f.cierres_formulario, f.cierres_landing, f.cierres_referido,
               f.cierres_referido_aporte, f.cierres_oficina, f.cierres_otros, f.upgrade, f.renovacion, f.renovacion_aporte,
               f.desglose_disponible), E'\n' order by f.analista_id nulls first), ''))
        into v_t from private.conversion_divisor_empresa(v_mes, v_hasta) f;
      insert into b11_salidas values ('divisor_empresa ' || v_mes, v_t, null);
    exception when others then insert into b11_salidas values ('divisor_empresa ' || v_mes, 'ERROR', sqlerrm); end;

    begin
      select pg_catalog.md5(coalesce(pg_catalog.string_agg(t::text, E'\n' order by t::text), ''))
        into v_t from private.conversion_cierres(v_ini, v_fin, v_mes, true, null::uuid[], private.peso_referido_conversion(v_mes), null::uuid[]) t;
      insert into b11_salidas values ('cierres ' || v_mes, v_t, null);
    exception when others then insert into b11_salidas values ('cierres ' || v_mes, 'ERROR', sqlerrm); end;

    begin
      v_j := pg_catalog.to_jsonb(crm.conversion_mensual_fn(v_mes));
      insert into b11_salidas values ('conversion_mensual ' || v_mes, pg_catalog.md5(pg_temp.b11_limpio(v_j)), null);
    exception when others then insert into b11_salidas values ('conversion_mensual ' || v_mes, 'ERROR', sqlerrm); end;
  end loop;

  -- Un rango libre que cruza meses (en vivo).
  begin
    v_j := crm.conversion_divisor_coordinacion_fn(null, '2026-09-15'::date, '2026-10-05'::date);
    insert into b11_salidas values ('coordinacion rango', pg_catalog.md5(pg_temp.b11_limpio(v_j)), 'base_cargada: ' || pg_temp.b11_base(v_j));
  exception when others then insert into b11_salidas values ('coordinacion rango', 'ERROR', sqlerrm); end;
  begin
    v_j := crm.metricas_conversiones_equipo_fn('2026-09-15'::date, '2026-10-05'::date);
    insert into b11_salidas values ('equipo rango', pg_catalog.md5(pg_temp.b11_limpio(v_j)), null);
  exception when others then insert into b11_salidas values ('equipo rango', 'ERROR', sqlerrm); end;
end;
$paridad$;

select etiqueta, huella, coalesce(nota, '') from b11_salidas order by etiqueta;
rollback;
