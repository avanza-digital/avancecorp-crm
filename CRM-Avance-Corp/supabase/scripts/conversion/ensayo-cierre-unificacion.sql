-- =========================================================================
-- ENSAYO DEL CIERRE DE MES · la prueba de aceptacion de la unificacion
-- =========================================================================
-- Responde, contra PRODUCCION y sin escribir nada, a la pregunta que define el
-- trabajo: «se cierra un mes y todas las pantallas siguen diciendo lo mismo».
--
-- Sella agosto de verdad, anula un cierre suyo (2 puntos de deuda) y compara
-- las cinco puertas sobre el mes abierto. Todo dentro de una transaccion que
-- termina en `rollback`: `crm.cerrar_periodo` no tiene ningun efecto fuera de
-- las tablas —comprobado el 23/09: ni `pg_notify`, ni `net.http`, ni `dblink`—
-- asi que el rollback lo deshace entero.
--
-- COMO SE CORRE:
--   supabase db query --linked --file supabase/scripts/conversion/ensayo-cierre-unificacion.sql
-- Termina SIEMPRE en `raise`, asi que la salida llega como un error. Eso es lo
-- que garantiza que no escribe.
--
-- RESULTADO DEL 23/09/2026, con la Ola 1b ya en produccion:
--
--                  SIN deuda              CON deuda
--   #4 grande      1218/52,650=4,32      1218/50,650=4,16
--   oficial        1218/52,650=4,32      1218/50,650=4,16
--   #6 suma        50,650                 48,650
--   #7 suma        49,650                 47,650
--   #8 suma        49,650                 47,650
--   -> los cinco restan exactamente 2, y la #4 es la oficial byte a byte.
--
-- ANTES de la Ola 1b, la #4 y la #6 se habrian quedado en 52,650 mientras la
-- oficial bajaba a 50,650: dos porcentajes del mismo mes.
--
-- La diferencia constante de 1,0 entre la #6 (50,650) y las #7/#8 (49,650) NO
-- es una discrepancia: es la parte que queda FUERA DEL ROSTER, que la #6 suma y
-- el ranking de metas no. Se mantiene identica antes y despues, que es lo que
-- prueba que no es deriva.
--
-- Y sellar, por si solo, NO mueve el numero: medido aparte sobre agosto,
-- 802/40,100 = 5,00 % antes y despues del sello.
-- =========================================================================

begin;
do $e$
declare
  v_claims text := current_setting('request.jwt.claims', true);
  v_ger uuid; v_ago date := '2026-08-01'::date;
  v_sep date := date_trunc('month',(now() at time zone 'America/Lima'))::date;
  v_hoy date := (now() at time zone 'America/Lima')::date;
  v_vic uuid; v_lead uuid; n jsonb;
  a4 text; a6 numeric; a7 numeric; a8 numeric; aof text;
  b4 text; b6 numeric; b7 numeric; b8 numeric; bof text;
begin
  select e.perfil_id into v_ger from crm.equipo e
   where e.rol_crm='gerencia' and e.activo and private.rol_crm(e.perfil_id)='gerencia'
   order by e.perfil_id limit 1;
  perform set_config('request.jwt.claims', jsonb_build_object('sub',v_ger,'role','authenticated')::text, true);

  perform crm.cerrar_periodo(v_ago);            -- AGOSTO QUEDA SELLADO

  -- Septiembre (mes abierto), ANTES de que llegue la deuda de agosto
  n := crm.metricas_conversiones_fn(v_sep, v_hoy) -> 'nucleo';
  a4 := format('%s/%s=%s', n->>'divisor', n->>'numerador', n->>'conversion_pct');
  aof := (select format('%s/%s=%s', x->>'divisor', x->>'numerador', x->>'conversion_pct')
            from (select crm.conversion_mensual_fn(v_sep)->'total' as x) q);
  select coalesce(sum((f.e->>'nucleo_numerador')::numeric),0) into a6
    from jsonb_array_elements(crm.metricas_conversiones_equipo_fn(v_sep, v_hoy)->'responsables') f(e);
  select coalesce(sum((f.e->>'numerador')::numeric),0) into a7
    from jsonb_array_elements(crm.cumplimiento_metas_fn(v_sep)->'vendedores') f(e);
  select coalesce(sum((f.e->>'numerador')::numeric),0) into a8
    from jsonb_array_elements(crm.cumplimiento_metas_sin_cartera_fn(v_sep)->'vendedores') f(e);
  perform set_config('request.jwt.claims', coalesce(v_claims,''), true);

  -- SE ANULA UN CIERRE DE AGOSTO: nace la deuda (2 puntos)
  select e.analista_id, e.lead_id into v_vic, v_lead
    from private.conversion_episodios(v_sep::timestamptz,(v_sep+interval '1 month')::timestamptz, v_sep, true, null, 1) e
   where e.analista_id is not null and e.lead_id is not null and e.tipo='cierre' limit 1;
  insert into crm.ajustes_mes_cerrado (vendedor_id, periodo_origen, lead_id, motivo, creado_por,
    numerador, capital_pen, capital_usd, detalle, pendiente_numerador, pendiente_pen, pendiente_usd, pendiente_detalle)
  values (v_vic, v_ago, v_lead, 'ENSAYO', v_vic, 2,0,0,'[]'::jsonb, 2,0,0,'[]'::jsonb);

  perform set_config('request.jwt.claims', jsonb_build_object('sub',v_ger,'role','authenticated')::text, true);
  n := crm.metricas_conversiones_fn(v_sep, v_hoy) -> 'nucleo';
  b4 := format('%s/%s=%s', n->>'divisor', n->>'numerador', n->>'conversion_pct');
  bof := (select format('%s/%s=%s', x->>'divisor', x->>'numerador', x->>'conversion_pct')
            from (select crm.conversion_mensual_fn(v_sep)->'total' as x) q);
  select coalesce(sum((f.e->>'nucleo_numerador')::numeric),0) into b6
    from jsonb_array_elements(crm.metricas_conversiones_equipo_fn(v_sep, v_hoy)->'responsables') f(e);
  select coalesce(sum((f.e->>'numerador')::numeric),0) into b7
    from jsonb_array_elements(crm.cumplimiento_metas_fn(v_sep)->'vendedores') f(e);
  select coalesce(sum((f.e->>'numerador')::numeric),0) into b8
    from jsonb_array_elements(crm.cumplimiento_metas_sin_cartera_fn(v_sep)->'vendedores') f(e);
  perform set_config('request.jwt.claims', coalesce(v_claims,''), true);

  raise exception E'AGOSTO SELLADO + 2 PUNTOS DE DEUDA · septiembre (mes abierto)\n                 SIN deuda              CON deuda\n  #4 grande      %      %\n  oficial        %      %\n  #6 suma        %                 %\n  #7 suma        %                 %\n  #8 suma        %                 %\n  ---\n  ¿los cinco se movieron IGUAL? %',
    a4, b4, aof, bof, a6, b6, a7, b7, a8, b8,
    case when (a6-b6)=2 and (a7-b7)=2 and (a8-b8)=2 and b4=bof then 'SI, los cinco restan 2 y #4 = oficial'
         else format('NO · deltas 6=%s 7=%s 8=%s · #4=%s oficial=%s', a6-b6, a7-b7, a8-b8, b4, bof) end;
end $e$;
rollback;
