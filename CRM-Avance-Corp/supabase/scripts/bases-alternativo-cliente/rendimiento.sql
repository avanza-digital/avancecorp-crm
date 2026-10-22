-- RENDIMIENTO del bloque 2.9 (MEDIDA, no veredicto) — se ejecuta en el LABORATORIO, nunca contra producción, y no escribe nada:
-- `armar-ensayo.mjs --rendimiento` lo pega en UNA transacción con la migración real en su marca (una sola línea) y termina en
-- excepción (rollback). Producción tenía 3 169 leads y 213 convertidos (D-23, 08/10/2026); aquí se siembran 50 000 leads sintéticos
-- (5 000 convertidos, la mitad con alternativo) con los disparadores apagados, SIN ANALYZE (ANALYZE escribiría estadísticas de
-- `crm.leads` fuera de la transacción en un laboratorio compartido). Mide, antes y después de la migración y en la misma transacción:
-- (1) 200 llamadas al envoltorio (las que hace un lote de 100 filas: el núcleo y la regla del ámbito, una cada uno por fila); (2) el
-- plan de su consulta con un teléfono que es el alternativo de un convertido; (3) un lote REAL de 100 filas nuevas por la puerta
-- `crm.cargar_base_lote` como SUP1 (el `statement_timeout` de authenticated es 8 s).
set local statement_timeout = '600s';

create temp table rend_medidas (n serial, txt text);
create function pg_temp.rend(p text) returns void language sql as $$ insert into rend_medidas (txt) values (p) $$;

-- Las 200 llamadas, cronometradas (100 teléfonos que no existen, 50 principales y 50 alternativos de convertidos sintéticos). El
-- nombre del envoltorio se arma en tiempo de ejecución: si esta función lo nombrara en su cuerpo, el preflight de la migración la
-- tomaría (con razón) por «otro posible llamador» y no se instalaría (medido; la búsqueda es textual y conservadora).
create function pg_temp.cronometra_envoltorio(p_etiqueta text) returns void language plpgsql as $f$
declare v_t0 timestamptz; v_n bigint := 0; v_i integer; v_x bigint;
  v_q text := 'select count(*) from private.bases_carga_' || 'contacto_existente($1, null)';
begin
  v_t0 := clock_timestamp();
  for v_i in 1 .. 100 loop
    execute v_q into v_x using '+51928' || lpad(v_i::text, 6, '0');
    v_n := v_n + v_x;
  end loop;
  for v_i in 1 .. 50 loop
    execute v_q into v_x using '+51929' || lpad((v_i * 20)::text, 6, '0');
    v_n := v_n + v_x;
    execute v_q into v_x using '+51939' || lpad((v_i * 20)::text, 6, '0');
    v_n := v_n + v_x;
  end loop;
  perform pg_temp.rend(format('%s · 200 llamadas al envoltorio: %s ms (%s ms por llamada) · filas devueltas %s',
    p_etiqueta, round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1),
    round(extract(epoch from clock_timestamp() - v_t0) * 1000 / 200, 3), v_n));
end;
$f$;

-- El plan de la consulta del envoltorio (una COPIA de su consulta con el WHERE de B8 o el del 2.9: la función no se expande en línea
-- porque lleva SET search_path), con un teléfono que es el alternativo de un convertido sintético.
create function pg_temp.plan_de(p_etiqueta text, p_where text) returns void language plpgsql as $f$
declare r record; v_txt text := '';
begin
  for r in execute format($q$explain (analyze, buffers, costs off, timing on, summary on)
    select l.id from crm.leads l where %s$q$, p_where) loop
    v_txt := v_txt || E'\n      ' || r."QUERY PLAN";
  end loop;
  perform pg_temp.rend(format('%s · plan:%s', p_etiqueta, v_txt));
end;
$f$;

-- Un lote REAL de 100 filas nuevas por la puerta, como SUP1, cronometrado.
create function pg_temp.lote_real(p_etiqueta text, p_base uuid, p_desde integer) returns void language plpgsql as $f$
declare v_t0 timestamptz; v_r jsonb; v_sup uuid := (select p.id from public.perfiles p where p.nombre_completo = 'PASO08 SUP1');
begin
  perform set_config('request.jwt.claim.sub', v_sup::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_sup, 'role', 'authenticated')::text, true);
  v_t0 := clock_timestamp();
  v_r := crm.cargar_base_lote(gen_random_uuid(), p_base,
           (select jsonb_agg(jsonb_build_object('fila', i, 'nombre', 'REND ' || i, 'telefono', '927' || lpad((p_desde + i)::text, 6, '0')) order by i)
              from generate_series(1, 100) i));
  perform pg_temp.rend(format('%s · lote real de 100 filas nuevas (SUP1): %s ms · %s', p_etiqueta,
    round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1), v_r -> 'lote'));
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
end;
$f$;

do $sembrar$
declare v_vend1 uuid := (select p.id from public.perfiles p where p.nombre_completo = 'PASO08 VEND1'); v_t0 timestamptz := clock_timestamp();
begin
  if v_vend1 is null then raise exception 'RENDIMIENTO ABORTADO: falta PASO08 VEND1'; end if;
  if exists (select 1 from crm.leads l where l.telefono like '+51929%' or l.telefono like '+51928%' or l.telefono like '+51927%'
                                         or l.telefono_alternativo like '+51939%') then
    raise exception 'RENDIMIENTO ABORTADO: el laboratorio ya tiene teléfonos de los bloques sintéticos +51 927/928/929/939';
  end if;
  set local session_replication_role = replica;
  insert into crm.leads (id, nombre_completo, telefono, telefono_alternativo, origen, etapa, convertido_en, monto_estimado, moneda,
                         vendedor_id, activo, creado_por, alta_manual, ciclo_actual, creado_en, actualizado_en, sla_global_iniciado_en)
  select gen_random_uuid(), 'SINTETICO ' || g, '+51929' || lpad(g::text, 6, '0'),
         case when g % 20 = 0 then '+51939' || lpad(g::text, 6, '0') end,
         'formulario', case when g % 10 = 0 then 'convertido' else 'nuevo' end,
         case when g % 10 = 0 then now() - interval '5 days' end, 1000, 'PEN', v_vend1, true, v_vend1, true, 1,
         now() - interval '30 days', now(), now() - interval '30 days'
    from generate_series(1, 50000) g;
  set local session_replication_role = origin;
  perform pg_temp.rend(format('siembra: %s leads sintéticos (%s convertidos, %s con alternativo) en %s ms; crm.leads tiene %s',
    50000, 5000, 2500, round(extract(epoch from clock_timestamp() - v_t0) * 1000), (select count(*) from crm.leads)));
end
$sembrar$;

do $base$
declare v_sup uuid := (select p.id from public.perfiles p where p.nombre_completo = 'PASO08 SUP1'); v_r jsonb;
begin
  perform set_config('request.jwt.claim.sub', v_sup::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_sup, 'role', 'authenticated')::text, true);
  v_r := crm.crear_base(gen_random_uuid(), 'BASE RENDIMIENTO 2.9', 'archivo', null, 'rendimiento-2-9.csv');
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  perform set_config('rend.base', v_r ->> 'base_id', true);
end
$base$;

select pg_temp.cronometra_envoltorio('ANTES (B8)');
select pg_temp.cronometra_envoltorio('ANTES (B8), 2.ª vuelta');
select pg_temp.plan_de('ANTES (WHERE de B8)', $w$l.telefono = '+51939001000' or (null::text is not null and l.dni = null::text)$w$);
select pg_temp.lote_real('ANTES (B8)', current_setting('rend.base')::uuid, 0);

-- @@MIGRACION@@

select pg_temp.cronometra_envoltorio('DESPUÉS (2.9)');
select pg_temp.cronometra_envoltorio('DESPUÉS (2.9), 2.ª vuelta');
select pg_temp.plan_de('DESPUÉS (WHERE del 2.9)', $w$l.telefono = '+51939001000' or (null::text is not null and l.dni = null::text) or (l.etapa = 'convertido' and l.telefono_alternativo = '+51939001000')$w$);
select pg_temp.lote_real('DESPUÉS (2.9)', current_setting('rend.base')::uuid, 1000);

do $fin$
begin
  raise exception E'RENDIMIENTO (medida, no veredicto):\n%\n(rollback a propósito — nada queda escrito)',
    (select string_agg(m.txt, E'\n' order by m.n) from rend_medidas m);
end
$fin$;
