-- MARCHA ATRAS de la Fase 6.c (las dos deudas declaradas) - v2.
-- Reemplazo INVERSO con LITERALES EXACTOS extraidos de la migracion (generado
-- por maquina: los bloques son los mismos bytes que la ida). Re-sella con las
-- razones de la F6.a. Postflight: huellas CRUDAS originales + trinquete OK.
begin;
set local lock_timeout = '5s';

do $$
declare v_def text; v_veces integer;
begin
  -- SERIES
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p where p.oid = 'crm.series_comerciales_fn(integer)'::regprocedure;
  v_veces := (length(v_def) - length(replace(v_def, $rb$  -- F6.c (v2, tras el P0 de Codex): la conversion OFICIAL de cada mes se pide
  -- A LA CAPA PUBLICADA (`crm.conversion_mensual_fn`, la de las pantallas), que sabe
  -- servir la FOTO SELLADA de un mes cerrado, restar los ajustes pendientes del
  -- mes abierto y redondear a DOS decimales. Recalcular aqui del nucleo habria
  -- creado la tercera copia de esa regla - lo que esta fase vino a matar.
  -- El rol sin permiso sobre la oficial (coordinador) recibe NULL, no un error:
  -- su serie de cohorte sigue viajando entera.
  serie_mensual_oficial as materialized (
    select m2.mes,
           (select private.conversion_mensual_pct_para_series(m2.mes)) as pct
    from (select (date_trunc('month', (now() at time zone 'America/Lima'))::date
                  - make_interval(months => (p_meses - 1 - g.n)))::date as mes
            from generate_series(0, p_meses - 1) as g(n)) m2
  ),
  meses as materialized ($rb$, ''))) / length($rb$  -- F6.c (v2, tras el P0 de Codex): la conversion OFICIAL de cada mes se pide
  -- A LA CAPA PUBLICADA (`crm.conversion_mensual_fn`, la de las pantallas), que sabe
  -- servir la FOTO SELLADA de un mes cerrado, restar los ajustes pendientes del
  -- mes abierto y redondear a DOS decimales. Recalcular aqui del nucleo habria
  -- creado la tercera copia de esa regla - lo que esta fase vino a matar.
  -- El rol sin permiso sobre la oficial (coordinador) recibe NULL, no un error:
  -- su serie de cohorte sigue viajando entera.
  serie_mensual_oficial as materialized (
    select m2.mes,
           (select private.conversion_mensual_pct_para_series(m2.mes)) as pct
    from (select (date_trunc('month', (now() at time zone 'America/Lima'))::date
                  - make_interval(months => (p_meses - 1 - g.n)))::date as mes
            from generate_series(0, p_meses - 1) as g(n)) m2
  ),
  meses as materialized ($rb$);
  if v_veces <> 1 then raise exception 'rollback F6.c: CTE insertado aparece % veces', v_veces; end if;
  v_def := replace(v_def, $rb$  -- F6.c (v2, tras el P0 de Codex): la conversion OFICIAL de cada mes se pide
  -- A LA CAPA PUBLICADA (`crm.conversion_mensual_fn`, la de las pantallas), que sabe
  -- servir la FOTO SELLADA de un mes cerrado, restar los ajustes pendientes del
  -- mes abierto y redondear a DOS decimales. Recalcular aqui del nucleo habria
  -- creado la tercera copia de esa regla - lo que esta fase vino a matar.
  -- El rol sin permiso sobre la oficial (coordinador) recibe NULL, no un error:
  -- su serie de cohorte sigue viajando entera.
  serie_mensual_oficial as materialized (
    select m2.mes,
           (select private.conversion_mensual_pct_para_series(m2.mes)) as pct
    from (select (date_trunc('month', (now() at time zone 'America/Lima'))::date
                  - make_interval(months => (p_meses - 1 - g.n)))::date as mes
            from generate_series(0, p_meses - 1) as g(n)) m2
  ),
  meses as materialized ($rb$, $rb$  meses as materialized ($rb$);
  v_def := replace(v_def, $rb$'version', 2,
    'conversion_mensual_pct', (select jsonb_agg(nm.pct order by nm.mes) from serie_mensual_oficial nm),$rb$, $rb$'version', 1,$rb$);
  v_def := replace(v_def, $rb$'conversion_cohorte_pct', jsonb_agg($rb$, $rb$'conversion_pct', jsonb_agg($rb$);
  execute v_def;

  -- REGISTRAR_AJUSTE
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p where p.oid = 'private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)'::regprocedure;
  v_veces := (length(v_def) - length(replace(v_def, $rb$-- F6.c (v2, tras el P1 de Codex): EL EPISODIO MANDA. El cierre puede caer a
  -- caballo del mes (convertido_en usa now() de transaccion y el ledger
  -- statement_timestamp(), caso documentado): se localiza el episodio canonico
  -- del lead SIN depender del mes de leads.convertido_en, y de el salen el
  -- PERIODO real, el referido y el peso. Cero episodios => la sancion de
  -- conversion vale CERO (nunca 1 en silencio) y queda alerta; mas de uno =>
  -- excepcion de integridad (el ledger solo permite una conversion por lead).
  select count(*),
         coalesce(bool_or(e.fue_referido), false),
         min(date_trunc('month', (e.fecha_numerador at time zone 'America/Lima'))::date)
    into v_n_episodios, v_referido, v_periodo_episodio
  from private.conversion_episodios(
         '1900-01-01'::timestamptz, '2100-01-01'::timestamptz,
         null::date, true, '{}'::uuid[], 1) e
  where e.lead_id = p_lead_id and e.tipo = 'cierre';

  if v_n_episodios > 1 then
    raise exception 'Integridad: el lead % tiene % episodios de cierre en el ledger', p_lead_id, v_n_episodios;
  end if;
  if v_n_episodios = 1 and v_periodo_episodio is distinct from v_periodo then
    -- El mes REAL del cierre es el del episodio: el cerrojo y la foto del mes
    -- sellado se toman sobre ese periodo (se re-toma el candado por si acaso).
    v_periodo := v_periodo_episodio;
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtext('crm.periodos_cerrados'),
      (v_periodo - date '2000-01-01')::integer);
    if not exists (select 1 from crm.periodos_cerrados pc where pc.periodo = v_periodo) then
      return null;
    end if;
  end if;
  if v_n_episodios = 0 then
    insert into private.vigia_alertas (fase, motivo)
    values ('f6c_ajuste_sin_episodio',
            format('lead %s: sin episodio de cierre en el ledger; la sancion de conversion vale 0', p_lead_id));
  end if;

  v_peso := private.peso_referido_conversion(v_periodo);$rb$, ''))) / length($rb$-- F6.c (v2, tras el P1 de Codex): EL EPISODIO MANDA. El cierre puede caer a
  -- caballo del mes (convertido_en usa now() de transaccion y el ledger
  -- statement_timestamp(), caso documentado): se localiza el episodio canonico
  -- del lead SIN depender del mes de leads.convertido_en, y de el salen el
  -- PERIODO real, el referido y el peso. Cero episodios => la sancion de
  -- conversion vale CERO (nunca 1 en silencio) y queda alerta; mas de uno =>
  -- excepcion de integridad (el ledger solo permite una conversion por lead).
  select count(*),
         coalesce(bool_or(e.fue_referido), false),
         min(date_trunc('month', (e.fecha_numerador at time zone 'America/Lima'))::date)
    into v_n_episodios, v_referido, v_periodo_episodio
  from private.conversion_episodios(
         '1900-01-01'::timestamptz, '2100-01-01'::timestamptz,
         null::date, true, '{}'::uuid[], 1) e
  where e.lead_id = p_lead_id and e.tipo = 'cierre';

  if v_n_episodios > 1 then
    raise exception 'Integridad: el lead % tiene % episodios de cierre en el ledger', p_lead_id, v_n_episodios;
  end if;
  if v_n_episodios = 1 and v_periodo_episodio is distinct from v_periodo then
    -- El mes REAL del cierre es el del episodio: el cerrojo y la foto del mes
    -- sellado se toman sobre ese periodo (se re-toma el candado por si acaso).
    v_periodo := v_periodo_episodio;
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtext('crm.periodos_cerrados'),
      (v_periodo - date '2000-01-01')::integer);
    if not exists (select 1 from crm.periodos_cerrados pc where pc.periodo = v_periodo) then
      return null;
    end if;
  end if;
  if v_n_episodios = 0 then
    insert into private.vigia_alertas (fase, motivo)
    values ('f6c_ajuste_sin_episodio',
            format('lead %s: sin episodio de cierre en el ledger; la sancion de conversion vale 0', p_lead_id));
  end if;

  v_peso := private.peso_referido_conversion(v_periodo);$rb$);
  if v_veces <> 1 then raise exception 'rollback F6.c: bloque R1 aparece % veces', v_veces; end if;
  v_def := replace(v_def, $rb$-- F6.c (v2, tras el P1 de Codex): EL EPISODIO MANDA. El cierre puede caer a
  -- caballo del mes (convertido_en usa now() de transaccion y el ledger
  -- statement_timestamp(), caso documentado): se localiza el episodio canonico
  -- del lead SIN depender del mes de leads.convertido_en, y de el salen el
  -- PERIODO real, el referido y el peso. Cero episodios => la sancion de
  -- conversion vale CERO (nunca 1 en silencio) y queda alerta; mas de uno =>
  -- excepcion de integridad (el ledger solo permite una conversion por lead).
  select count(*),
         coalesce(bool_or(e.fue_referido), false),
         min(date_trunc('month', (e.fecha_numerador at time zone 'America/Lima'))::date)
    into v_n_episodios, v_referido, v_periodo_episodio
  from private.conversion_episodios(
         '1900-01-01'::timestamptz, '2100-01-01'::timestamptz,
         null::date, true, '{}'::uuid[], 1) e
  where e.lead_id = p_lead_id and e.tipo = 'cierre';

  if v_n_episodios > 1 then
    raise exception 'Integridad: el lead % tiene % episodios de cierre en el ledger', p_lead_id, v_n_episodios;
  end if;
  if v_n_episodios = 1 and v_periodo_episodio is distinct from v_periodo then
    -- El mes REAL del cierre es el del episodio: el cerrojo y la foto del mes
    -- sellado se toman sobre ese periodo (se re-toma el candado por si acaso).
    v_periodo := v_periodo_episodio;
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtext('crm.periodos_cerrados'),
      (v_periodo - date '2000-01-01')::integer);
    if not exists (select 1 from crm.periodos_cerrados pc where pc.periodo = v_periodo) then
      return null;
    end if;
  end if;
  if v_n_episodios = 0 then
    insert into private.vigia_alertas (fase, motivo)
    values ('f6c_ajuste_sin_episodio',
            format('lead %s: sin episodio de cierre en el ledger; la sancion de conversion vale 0', p_lead_id));
  end if;

  v_peso := private.peso_referido_conversion(v_periodo);$rb$, $rb$select coalesce(bool_or(la.origen = 'referido'), false) into v_referido
  from crm.lead_asignaciones la
  where la.lead_id = p_lead_id and la.resultado = 'convertido';

  v_peso := private.peso_referido_conversion(v_periodo);$rb$);
  v_def := replace(v_def, $rb$v_numerador := case when v_n_episodios = 0 then 0
                       when v_referido then v_peso else 1 end;$rb$, $rb$v_numerador := case when v_referido then v_peso else 1 end;$rb$);
  v_def := replace(v_def, $rb$  v_numerador   numeric;
  v_n_episodios integer;
  v_periodo_episodio date;$rb$, $rb$  v_numerador   numeric;$rb$);
  execute v_def;
end $$;

drop function if exists private.conversion_mensual_pct_para_series(date);

-- Re-sello con las razones de la F6.a (huellas de los cuerpos restaurados).
update private.analitica_leads_citas_exenciones
   set huella = (select md5(regexp_replace(regexp_replace(
                   lower(coalesce(p.prosrc, pg_get_functiondef(p.oid))),
                   '--[^\n]*',' ','g'),'/\*.*?\*/',' ','g'))
                 from pg_proc p where p.oid = 'crm.series_comerciales_fn(integer)'::regprocedure),
       razon = 'MIXTA CON DEUDA: los cierres salen del nucleo, PERO su conversion_pct es una SEGUNDA formula - cohorte por mes de entrada SIN peso de referido, calculada aqui en crudo (2,8 pct vs 7,0 pct del nucleo en agosto, medido). Deuda declarada del Bloque B: convertirla o renombrar la clave a conversion_cohorte.'
 where objeto = 'crm.series_comerciales_fn(integer)';
update private.analitica_leads_citas_exenciones
   set huella = (select md5(regexp_replace(regexp_replace(
                   lower(coalesce(p.prosrc, pg_get_functiondef(p.oid))),
                   '--[^\n]*',' ','g'),'/\*.*?\*/',' ','g'))
                 from pg_proc p where p.oid = 'private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)'::regprocedure),
       razon = 'CON DEUDA: el capital sale de capital_episodios, PERO el numerador del ajuste se recalcula LOCALMENTE (peso_referido a mano) y su rama de coops replica condicion por condicion a produccion_mes_por_vendedor. Deuda declarada del Bloque B: que beba del puente del sello.'
 where objeto = 'private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)';
update private.analitica_lc_sello
   set sello = private.huella_exenciones_analitica_lc(), sellado_en = now()
 where id;

-- POSTFLIGHT: huellas CRUDAS de vuelta a las originales del 30/08 + trinquete OK.
do $$
declare v_h text; v_verd text;
begin
  select md5(p.prosrc) into v_h from pg_proc p
   where p.oid = 'crm.series_comerciales_fn(integer)'::regprocedure;
  if v_h is distinct from '478c16594a88f67c365625c6097c517c' then
    raise exception 'rollback F6.c: series no volvio a su huella (%)', v_h;
  end if;
  select md5(p.prosrc) into v_h from pg_proc p
   where p.oid = 'private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)'::regprocedure;
  if v_h is distinct from '8669f55703e4d1493aaa77f228d35235' then
    raise exception 'rollback F6.c: registrar_ajuste no volvio a su huella (%)', v_h;
  end if;
  select private.assert_analitica_leads_citas() into v_verd;
  if v_verd not like 'OK:%' then
    raise exception 'rollback F6.c: el trinquete no dio OK: %', v_verd;
  end if;
end $$;

commit;
