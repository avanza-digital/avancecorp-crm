-- Registra la version 20260830140000 CON su cuerpo - FAIL-CLOSED, etiqueta propia.
do $registro_f6c$
declare v_actual text[];
begin
  select statements into v_actual from supabase_migrations.schema_migrations where version = '20260830140000';
  if found and v_actual is not null and v_actual <> array[$mig_f6_c$-- P-055 Fase 6.c - LAS DOS DEUDAS DECLARADAS, CERRADAS.
--
-- ORDEN DE MIGUEL (30/08): «cerremos las 2 deudas declaradas».
--
-- 1) `crm.series_comerciales_fn`: su `conversion_pct` era una SEGUNDA formula
--    (cohorte por mes de entrada, sin peso de referido). MEDIDO antes de tocar:
--    la formula es el ESPEJO DELIBERADO del front (decision de Miguel del
--    27/08: la cifra grande es el BRUTO/cohorte) y la RPC NO TIENE NI UN
--    CONSUMIDOR (el front calcula su serie en el navegador; nadie mas la
--    llama). El pecado era el NOMBRE sin apellido. Cierre: la clave pasa a
--    `conversion_cohorte_pct` y el payload gana `conversion_mensual_pct` - la
--    conversion OFICIAL de cada mes, del nucleo - para que el front, cuando
--    migre, pueda pintar las dos lineas con su nombre. `version` sube a 2.
--
-- 2) `private.registrar_ajuste_si_mes_cerrado`: su numerador se recalculaba
--    LOCALMENTE (bool_or sobre lead_asignaciones + peso a mano). Cierre: el
--    referido sale del EPISODIO del nucleo (`conversion_episodios`,
--    anulados incluidos - el cierre ya esta anulado cuando esta funcion corre).
--    La rama (b) de cooperativas NO ERA DEUDA y no se toca: la F4 decidio POR
--    SEMANTICA que el nucleo de capital solo carga capital QUE EXISTE, y la
--    deuda necesita el monto ORIGINAL de una coop ya anulada. La deriva de esa
--    regla copiada la vigila el trinquete de la F6.a: las DOS funciones
--    (esta y `produccion_mes_por_vendedor`) estan selladas por huella - si
--    cualquiera cambia de cuerpo, su exencion caduca y el gate se pone rojo.
--
-- Las huellas de ambos exentos cambian: esta migracion las RE-SELLA con sus
-- razones nuevas (ya sin la palabra deuda) y re-sella la lista.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- =====================================================================
-- 0) PREFLIGHT por huella cruda (md5 de prosrc, medido el 30/08).
-- =====================================================================
do $$
declare v_h text;
begin
  select md5(p.prosrc) into v_h from pg_proc p
   where p.oid = 'crm.series_comerciales_fn(integer)'::regprocedure;
  if v_h is distinct from '478c16594a88f67c365625c6097c517c' then
    raise exception 'F6.c preflight: series_comerciales_fn cambio (huella %)', v_h;
  end if;
  select md5(p.prosrc) into v_h from pg_proc p
   where p.oid = 'private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)'::regprocedure;
  if v_h is distinct from '8669f55703e4d1493aaa77f228d35235' then
    raise exception 'F6.c preflight: registrar_ajuste_si_mes_cerrado cambio (huella %)', v_h;
  end if;
end $$;

-- El ayudante de la serie: UNA cifra oficial por mes. La oficial DE PANTALLAS
-- es `crm.conversion_mensual_fn` (la variante sin_cartera esta cerrada por
-- permiso incluso a gerencia: solo la llama el propio servidor). Si la oficial
-- le niega el permiso al llamante (coordinador), NULL - la serie no revienta.
-- El ayudante corre como DEFINER pero la oficial re-impone SU propia puerta
-- leyendo auth.uid(), asi que el recorte por rol se conserva.
create or replace function private.conversion_mensual_pct_para_series(p_mes date)
returns numeric
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare v numeric;
begin
  begin
    select (crm.conversion_mensual_fn(p_mes)::jsonb #>> '{total,conversion_pct}')::numeric
      into v;
  exception when insufficient_privilege then
    return null;
  end;
  return v;
end;
$function$;

revoke all on function private.conversion_mensual_pct_para_series(date) from public;

-- =====================================================================
-- 1) SERIES: el nombre dice la verdad y el nucleo entra al payload.
--    Reemplazo ANCLADO sobre el cuerpo vivo (3 anclas, cada una 1 vez).
-- =====================================================================
do $$
declare v_def text; v_veces integer; v_ancla text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p where p.oid = 'crm.series_comerciales_fn(integer)'::regprocedure;

  -- ancla 1: la serie mensual del NUCLEO entra como CTE tras la de cierres.
  v_ancla := $a$  meses as materialized ($a$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then raise exception 'F6.c: ancla 1 aparece % veces', v_veces; end if;
  v_def := replace(v_def, v_ancla, $b$  -- F6.c (v2, tras el P0 de Codex): la conversion OFICIAL de cada mes se pide
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
  meses as materialized ($b$);

  -- ancla 2: la clave vieja gana su apellido.
  v_ancla := $a$'conversion_pct', jsonb_agg($a$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then raise exception 'F6.c: ancla 2 aparece % veces', v_veces; end if;
  v_def := replace(v_def, v_ancla, $b$'conversion_cohorte_pct', jsonb_agg($b$);

  -- ancla 3: la serie del nucleo entra al payload y version sube a 2.
  v_ancla := $a$'version', 1,$a$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then raise exception 'F6.c: ancla 3 aparece % veces', v_veces; end if;
  v_def := replace(v_def, v_ancla, $b$'version', 2,
    'conversion_mensual_pct', (select jsonb_agg(nm.pct order by nm.mes) from serie_mensual_oficial nm),$b$);

  execute v_def;
end $$;

-- =====================================================================
-- 2) REGISTRAR_AJUSTE: el referido sale del EPISODIO del nucleo.
-- =====================================================================
do $$
declare v_def text; v_veces integer; v_ancla text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p where p.oid = 'private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)'::regprocedure;

  v_ancla := $a$select coalesce(bool_or(la.origen = 'referido'), false) into v_referido
  from crm.lead_asignaciones la
  where la.lead_id = p_lead_id and la.resultado = 'convertido';

  v_peso := private.peso_referido_conversion(v_periodo);$a$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then raise exception 'F6.c: ancla R1 aparece % veces', v_veces; end if;
  v_def := replace(v_def, v_ancla, $b$-- F6.c (v2, tras el P1 de Codex): EL EPISODIO MANDA. El cierre puede caer a
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

  v_peso := private.peso_referido_conversion(v_periodo);$b$);

  -- el numerador: 0 sin episodio, el peso del PERIODO REAL con el.
  v_ancla := $a$v_numerador := case when v_referido then v_peso else 1 end;$a$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then raise exception 'F6.c: ancla R2 aparece % veces', v_veces; end if;
  v_def := replace(v_def, v_ancla,
    $b$v_numerador := case when v_n_episodios = 0 then 0
                       when v_referido then v_peso else 1 end;$b$);

  -- las variables nuevas
  v_ancla := $a$  v_numerador   numeric;$a$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then raise exception 'F6.c: ancla R3 aparece % veces', v_veces; end if;
  v_def := replace(v_def, v_ancla, $b$  v_numerador   numeric;
  v_n_episodios integer;
  v_periodo_episodio date;$b$);

  execute v_def;
end $$;

-- =====================================================================
-- 3) RE-SELLAR los dos exentos con sus razones nuevas (ya sin deuda).
-- =====================================================================
update private.analitica_leads_citas_exenciones
   set huella = (select md5(regexp_replace(regexp_replace(
                   lower(coalesce(p.prosrc, pg_get_functiondef(p.oid))),
                   '--[^\n]*',' ','g'),'/\*.*?\*/',' ','g'))
                 from pg_proc p
                 where p.oid = 'crm.series_comerciales_fn(integer)'::regprocedure),
       razon = 'MIXTA: la conversion mensual OFICIAL viaja en conversion_mensual_pct (del nucleo, peso del mes); conversion_cohorte_pct es el espejo deliberado del front (decision de Miguel 27/08: la cifra grande es el BRUTO por mes de entrada) y su nombre ya dice su apellido. Los counts crudos restantes cuentan altas y cohorte de entrada.'
 where objeto = 'crm.series_comerciales_fn(integer)';

update private.analitica_leads_citas_exenciones
   set huella = (select md5(regexp_replace(regexp_replace(
                   lower(coalesce(p.prosrc, pg_get_functiondef(p.oid))),
                   '--[^\n]*',' ','g'),'/\*.*?\*/',' ','g'))
                 from pg_proc p
                 where p.oid = 'private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)'::regprocedure),
       razon = 'El numerador del ajuste sale del EPISODIO del nucleo (F6.c). La rama de coops anuladas queda cruda POR SEMANTICA DE LA F4: el nucleo de capital solo carga capital que existe y la deuda necesita el monto ORIGINAL de la coop anulada; la deriva de esa regla copiada la vigila este mismo trinquete (produccion_mes_por_vendedor tambien esta sellada).'
 where objeto = 'private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)';

update private.analitica_lc_sello
   set sello = private.huella_exenciones_analitica_lc(), sellado_en = now()
 where id;

-- =====================================================================
-- 4) POSTFLIGHT.
-- =====================================================================
do $$
declare v_verd text; v_src text;
begin
  select p.prosrc into v_src from pg_proc p
   where p.oid = 'crm.series_comerciales_fn(integer)'::regprocedure;
  if strpos(v_src, $k$'conversion_pct'$k$) > 0 then
    raise exception 'F6.c postflight: series conserva la clave sin apellido';
  end if;
  if strpos(v_src, $k$'conversion_cohorte_pct'$k$) = 0
     or strpos(v_src, $k$'conversion_mensual_pct'$k$) = 0 then
    raise exception 'F6.c postflight: a series le falta una de las dos claves nuevas';
  end if;

  select p.prosrc into v_src from pg_proc p
   where p.oid = 'private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)'::regprocedure;
  if strpos(v_src, 'conversion_episodios') = 0 then
    raise exception 'F6.c postflight: registrar_ajuste no bebe del nucleo';
  end if;
  if v_src ~ 'bool_or\(la\.origen' then
    raise exception 'F6.c postflight: registrar_ajuste conserva el calculo local del referido';
  end if;

  -- SMOKE de verdad (P1-2 del auditor): plpgsql no resuelve identificadores al
  -- crearse — la funcion nueva se EJECUTA como gerencia y se le exige la forma.
  declare
    v_ger uuid; v_j jsonb;
  begin
    select e.perfil_id into v_ger from crm.equipo e where e.rol_crm = 'gerencia' and e.activo limit 1;
    perform set_config('request.jwt.claims', json_build_object('sub', v_ger, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select crm.series_comerciales_fn(2)::jsonb into v_j;
    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
    if (v_j->>'version')::int <> 2
       or not (v_j ? 'conversion_cohorte_pct')
       or not (v_j ? 'conversion_mensual_pct')
       or jsonb_array_length(v_j->'conversion_mensual_pct') <> 2 then
      raise exception 'F6.c postflight: el smoke de series no cuadra: %', left(v_j::text, 300);
    end if;
  end;

  -- El trinquete entero, en verde con las huellas re-selladas.
  select private.assert_analitica_leads_citas() into v_verd;
  if v_verd not like 'OK:%' then
    raise exception 'F6.c postflight: el trinquete no dio OK: %', v_verd;
  end if;
end $$;

commit;
$mig_f6_c$] then
    raise exception 'La version 20260830140000 ya existe con OTRO cuerpo';
  end if;
  insert into supabase_migrations.schema_migrations (version, name, statements)
  values ('20260830140000', 'crm_f6_c_deudas_declaradas', array[$mig_f6_c$-- P-055 Fase 6.c - LAS DOS DEUDAS DECLARADAS, CERRADAS.
--
-- ORDEN DE MIGUEL (30/08): «cerremos las 2 deudas declaradas».
--
-- 1) `crm.series_comerciales_fn`: su `conversion_pct` era una SEGUNDA formula
--    (cohorte por mes de entrada, sin peso de referido). MEDIDO antes de tocar:
--    la formula es el ESPEJO DELIBERADO del front (decision de Miguel del
--    27/08: la cifra grande es el BRUTO/cohorte) y la RPC NO TIENE NI UN
--    CONSUMIDOR (el front calcula su serie en el navegador; nadie mas la
--    llama). El pecado era el NOMBRE sin apellido. Cierre: la clave pasa a
--    `conversion_cohorte_pct` y el payload gana `conversion_mensual_pct` - la
--    conversion OFICIAL de cada mes, del nucleo - para que el front, cuando
--    migre, pueda pintar las dos lineas con su nombre. `version` sube a 2.
--
-- 2) `private.registrar_ajuste_si_mes_cerrado`: su numerador se recalculaba
--    LOCALMENTE (bool_or sobre lead_asignaciones + peso a mano). Cierre: el
--    referido sale del EPISODIO del nucleo (`conversion_episodios`,
--    anulados incluidos - el cierre ya esta anulado cuando esta funcion corre).
--    La rama (b) de cooperativas NO ERA DEUDA y no se toca: la F4 decidio POR
--    SEMANTICA que el nucleo de capital solo carga capital QUE EXISTE, y la
--    deuda necesita el monto ORIGINAL de una coop ya anulada. La deriva de esa
--    regla copiada la vigila el trinquete de la F6.a: las DOS funciones
--    (esta y `produccion_mes_por_vendedor`) estan selladas por huella - si
--    cualquiera cambia de cuerpo, su exencion caduca y el gate se pone rojo.
--
-- Las huellas de ambos exentos cambian: esta migracion las RE-SELLA con sus
-- razones nuevas (ya sin la palabra deuda) y re-sella la lista.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- =====================================================================
-- 0) PREFLIGHT por huella cruda (md5 de prosrc, medido el 30/08).
-- =====================================================================
do $$
declare v_h text;
begin
  select md5(p.prosrc) into v_h from pg_proc p
   where p.oid = 'crm.series_comerciales_fn(integer)'::regprocedure;
  if v_h is distinct from '478c16594a88f67c365625c6097c517c' then
    raise exception 'F6.c preflight: series_comerciales_fn cambio (huella %)', v_h;
  end if;
  select md5(p.prosrc) into v_h from pg_proc p
   where p.oid = 'private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)'::regprocedure;
  if v_h is distinct from '8669f55703e4d1493aaa77f228d35235' then
    raise exception 'F6.c preflight: registrar_ajuste_si_mes_cerrado cambio (huella %)', v_h;
  end if;
end $$;

-- El ayudante de la serie: UNA cifra oficial por mes. La oficial DE PANTALLAS
-- es `crm.conversion_mensual_fn` (la variante sin_cartera esta cerrada por
-- permiso incluso a gerencia: solo la llama el propio servidor). Si la oficial
-- le niega el permiso al llamante (coordinador), NULL - la serie no revienta.
-- El ayudante corre como DEFINER pero la oficial re-impone SU propia puerta
-- leyendo auth.uid(), asi que el recorte por rol se conserva.
create or replace function private.conversion_mensual_pct_para_series(p_mes date)
returns numeric
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare v numeric;
begin
  begin
    select (crm.conversion_mensual_fn(p_mes)::jsonb #>> '{total,conversion_pct}')::numeric
      into v;
  exception when insufficient_privilege then
    return null;
  end;
  return v;
end;
$function$;

revoke all on function private.conversion_mensual_pct_para_series(date) from public;

-- =====================================================================
-- 1) SERIES: el nombre dice la verdad y el nucleo entra al payload.
--    Reemplazo ANCLADO sobre el cuerpo vivo (3 anclas, cada una 1 vez).
-- =====================================================================
do $$
declare v_def text; v_veces integer; v_ancla text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p where p.oid = 'crm.series_comerciales_fn(integer)'::regprocedure;

  -- ancla 1: la serie mensual del NUCLEO entra como CTE tras la de cierres.
  v_ancla := $a$  meses as materialized ($a$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then raise exception 'F6.c: ancla 1 aparece % veces', v_veces; end if;
  v_def := replace(v_def, v_ancla, $b$  -- F6.c (v2, tras el P0 de Codex): la conversion OFICIAL de cada mes se pide
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
  meses as materialized ($b$);

  -- ancla 2: la clave vieja gana su apellido.
  v_ancla := $a$'conversion_pct', jsonb_agg($a$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then raise exception 'F6.c: ancla 2 aparece % veces', v_veces; end if;
  v_def := replace(v_def, v_ancla, $b$'conversion_cohorte_pct', jsonb_agg($b$);

  -- ancla 3: la serie del nucleo entra al payload y version sube a 2.
  v_ancla := $a$'version', 1,$a$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then raise exception 'F6.c: ancla 3 aparece % veces', v_veces; end if;
  v_def := replace(v_def, v_ancla, $b$'version', 2,
    'conversion_mensual_pct', (select jsonb_agg(nm.pct order by nm.mes) from serie_mensual_oficial nm),$b$);

  execute v_def;
end $$;

-- =====================================================================
-- 2) REGISTRAR_AJUSTE: el referido sale del EPISODIO del nucleo.
-- =====================================================================
do $$
declare v_def text; v_veces integer; v_ancla text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p where p.oid = 'private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)'::regprocedure;

  v_ancla := $a$select coalesce(bool_or(la.origen = 'referido'), false) into v_referido
  from crm.lead_asignaciones la
  where la.lead_id = p_lead_id and la.resultado = 'convertido';

  v_peso := private.peso_referido_conversion(v_periodo);$a$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then raise exception 'F6.c: ancla R1 aparece % veces', v_veces; end if;
  v_def := replace(v_def, v_ancla, $b$-- F6.c (v2, tras el P1 de Codex): EL EPISODIO MANDA. El cierre puede caer a
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

  v_peso := private.peso_referido_conversion(v_periodo);$b$);

  -- el numerador: 0 sin episodio, el peso del PERIODO REAL con el.
  v_ancla := $a$v_numerador := case when v_referido then v_peso else 1 end;$a$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then raise exception 'F6.c: ancla R2 aparece % veces', v_veces; end if;
  v_def := replace(v_def, v_ancla,
    $b$v_numerador := case when v_n_episodios = 0 then 0
                       when v_referido then v_peso else 1 end;$b$);

  -- las variables nuevas
  v_ancla := $a$  v_numerador   numeric;$a$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then raise exception 'F6.c: ancla R3 aparece % veces', v_veces; end if;
  v_def := replace(v_def, v_ancla, $b$  v_numerador   numeric;
  v_n_episodios integer;
  v_periodo_episodio date;$b$);

  execute v_def;
end $$;

-- =====================================================================
-- 3) RE-SELLAR los dos exentos con sus razones nuevas (ya sin deuda).
-- =====================================================================
update private.analitica_leads_citas_exenciones
   set huella = (select md5(regexp_replace(regexp_replace(
                   lower(coalesce(p.prosrc, pg_get_functiondef(p.oid))),
                   '--[^\n]*',' ','g'),'/\*.*?\*/',' ','g'))
                 from pg_proc p
                 where p.oid = 'crm.series_comerciales_fn(integer)'::regprocedure),
       razon = 'MIXTA: la conversion mensual OFICIAL viaja en conversion_mensual_pct (del nucleo, peso del mes); conversion_cohorte_pct es el espejo deliberado del front (decision de Miguel 27/08: la cifra grande es el BRUTO por mes de entrada) y su nombre ya dice su apellido. Los counts crudos restantes cuentan altas y cohorte de entrada.'
 where objeto = 'crm.series_comerciales_fn(integer)';

update private.analitica_leads_citas_exenciones
   set huella = (select md5(regexp_replace(regexp_replace(
                   lower(coalesce(p.prosrc, pg_get_functiondef(p.oid))),
                   '--[^\n]*',' ','g'),'/\*.*?\*/',' ','g'))
                 from pg_proc p
                 where p.oid = 'private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)'::regprocedure),
       razon = 'El numerador del ajuste sale del EPISODIO del nucleo (F6.c). La rama de coops anuladas queda cruda POR SEMANTICA DE LA F4: el nucleo de capital solo carga capital que existe y la deuda necesita el monto ORIGINAL de la coop anulada; la deriva de esa regla copiada la vigila este mismo trinquete (produccion_mes_por_vendedor tambien esta sellada).'
 where objeto = 'private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)';

update private.analitica_lc_sello
   set sello = private.huella_exenciones_analitica_lc(), sellado_en = now()
 where id;

-- =====================================================================
-- 4) POSTFLIGHT.
-- =====================================================================
do $$
declare v_verd text; v_src text;
begin
  select p.prosrc into v_src from pg_proc p
   where p.oid = 'crm.series_comerciales_fn(integer)'::regprocedure;
  if strpos(v_src, $k$'conversion_pct'$k$) > 0 then
    raise exception 'F6.c postflight: series conserva la clave sin apellido';
  end if;
  if strpos(v_src, $k$'conversion_cohorte_pct'$k$) = 0
     or strpos(v_src, $k$'conversion_mensual_pct'$k$) = 0 then
    raise exception 'F6.c postflight: a series le falta una de las dos claves nuevas';
  end if;

  select p.prosrc into v_src from pg_proc p
   where p.oid = 'private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)'::regprocedure;
  if strpos(v_src, 'conversion_episodios') = 0 then
    raise exception 'F6.c postflight: registrar_ajuste no bebe del nucleo';
  end if;
  if v_src ~ 'bool_or\(la\.origen' then
    raise exception 'F6.c postflight: registrar_ajuste conserva el calculo local del referido';
  end if;

  -- SMOKE de verdad (P1-2 del auditor): plpgsql no resuelve identificadores al
  -- crearse — la funcion nueva se EJECUTA como gerencia y se le exige la forma.
  declare
    v_ger uuid; v_j jsonb;
  begin
    select e.perfil_id into v_ger from crm.equipo e where e.rol_crm = 'gerencia' and e.activo limit 1;
    perform set_config('request.jwt.claims', json_build_object('sub', v_ger, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select crm.series_comerciales_fn(2)::jsonb into v_j;
    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
    if (v_j->>'version')::int <> 2
       or not (v_j ? 'conversion_cohorte_pct')
       or not (v_j ? 'conversion_mensual_pct')
       or jsonb_array_length(v_j->'conversion_mensual_pct') <> 2 then
      raise exception 'F6.c postflight: el smoke de series no cuadra: %', left(v_j::text, 300);
    end if;
  end;

  -- El trinquete entero, en verde con las huellas re-selladas.
  select private.assert_analitica_leads_citas() into v_verd;
  if v_verd not like 'OK:%' then
    raise exception 'F6.c postflight: el trinquete no dio OK: %', v_verd;
  end if;
end $$;

commit;
$mig_f6_c$])
  on conflict (version) do nothing;
end $registro_f6c$;
