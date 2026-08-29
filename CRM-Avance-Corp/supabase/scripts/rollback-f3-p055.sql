-- MARCHA ATRAS de la Fase 3 (P-055) — tren del 29/08 tras las DOS auditorias:
-- 20260829180000, 180500, 181000, 181500, 182000, 182200, 182300, 182500, 182800
-- (y la 183000 si se llego a aplicar desde snippets/).
--
-- Reescrita ENTERA por el hallazgo P1-4 de Codex: la version anterior no
-- borraba la puerta de la marca demo, no restauraba el CHECK del registro, no
-- restauraba de verdad la sancion y ademas borraba `es_demo` ANTES de quitarle
-- las funciones que la leian. Esta se deshace en el ORDEN INVERSO REAL y
-- termina ejecutable de punta a punta.
--
-- Cada bloque es tolerante: si esa pieza no llego a publicarse, sigue.
-- 🔴 El respaldo del rastro va a `private` (hallazgo B1): `public` es endpoint
-- de la Data API y una tabla nueva alli nace legible para `anon`.

begin;

-- 1) [183000, si se aplico] + [181000]: crear_contrato vuelve al original.
--    «Original» = el publicado por 20260829175638 (huella 2699cc72...), que una
--    sesion paralela dejo en produccion la tarde del 29/08.
do $r$
declare v_src text; v_huella text;
begin
  select p.prosrc, md5(p.prosrc) into v_src, v_huella
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname='public' and p.proname='crear_contrato';

  if v_huella = '2699cc72bc69073895881399c02d7815' then
    raise notice '1) crear_contrato ya es el original';
  elsif strpos(v_src, 'v_analista_cierre') > 0 then
    v_src := replace(v_src, E'\n  v_analista_cierre uuid;', '');
    -- el bloque termina en el UNICO 'end if;' seguido de linea en blanco; los
    -- 'end if;' internos van seguidos de texto y el motor los salta. El \n\n
    -- final es del ORIGINAL y se conserva (lookahead, no consumo).
    v_src := regexp_replace(v_src,
      '\n\n  -- EL ANALISTA QUE CIERRA \(decision 2 del plan P-055\).*?end if;(?=\n\n)', '', 's');
    v_src := replace(v_src, 'creado_por, analista_cierre_id
  ) values (', 'creado_por
  ) values (');
    v_src := replace(v_src, 'v_categoria, ''activo'', v_uid, v_analista_cierre
  ) returning', 'v_categoria, ''activo'', v_uid
  ) returning');
    if strpos(v_src, 'v_analista_cierre') > 0 then
      raise exception '1) No se pudo limpiar crear_contrato: revisar a mano';
    end if;
    execute format('create or replace function public.crear_contrato(p_contrato jsonb, p_cronograma jsonb) '
                   'returns jsonb language plpgsql security definer set search_path to '''' as %L', v_src);
    if (select md5(prosrc) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
        where n.nspname='public' and p.proname='crear_contrato') <> '2699cc72bc69073895881399c02d7815' then
      raise exception '1) crear_contrato restaurado NO da la huella original: ABORTA';
    end if;
    raise notice '1) crear_contrato restaurado (huella verificada)';
  else
    raise notice '1) crear_contrato sin rastro del parche';
  end if;
end $r$;

-- 2) [182800] La sancion vuelve a su cuerpo ORIGINAL (embebido y verificado:
--    md5 e07c89715b96ee2604ce435fea3e2c34). ANTES de tocar es_demo, porque la
--    version parcheada la lee.
create or replace function private.registrar_ajuste_si_mes_cerrado(
  p_lead_id uuid, p_motivo text, p_por uuid
) returns uuid language plpgsql security definer set search_path to ''
as $original$
declare
  v_lead        crm.leads%rowtype;
  v_periodo     date;
  v_acreditado  uuid;
  v_referido    boolean;
  v_peso        numeric;
  v_numerador   numeric;
  v_pen         numeric := 0;
  v_usd         numeric := 0;
  v_detalle     jsonb := '[]'::jsonb;
  v_id          uuid;
begin
  select * into v_lead from crm.leads where id = p_lead_id;
  if not found or v_lead.convertido_en is null then
    return null;
  end if;

  v_periodo := date_trunc('month', v_lead.convertido_en at time zone 'America/Lima')::date;

  -- ⚠️ EL CERROJO, antes de mirar si el mes esta cerrado. Sin el, una anulacion
  -- concurrente con el sellado de ESE mes lee «abierto» —porque el sello aun no
  -- ha commiteado—, devuelve NULL, y el cierre anulado se queda pagado para
  -- siempre. Misma clave que en `crm.cerrar_periodo`.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('crm.periodos_cerrados'),
    (v_periodo - date '2000-01-01')::integer
  );

  -- Mes ABIERTO: no hay deuda que registrar. El mes se recalcula y el cierre
  -- desaparece de el, que es el comportamiento de siempre.
  if not exists (select 1 from crm.periodos_cerrados pc where pc.periodo = v_periodo) then
    return null;
  end if;

  -- A quien se le descuenta: el mismo acreditado que usa la cuota.
  v_acreditado := coalesce(
    (select ca.acreditado_a from crm.cierres_avance_anulados ca where ca.lead_id = p_lead_id),
    private.vendedor_acreditado_del_cierre(p_lead_id));
  if v_acreditado is null then
    -- Sin acreditado no hay a quien descontarle. No se inventa un deudor.
    return null;
  end if;

  -- Lo que valia el cierre en la conversion. El origen sale del LEDGER (la foto
  -- del episodio), no de `crm.leads.origen`, que es una columna viva.
  select coalesce(bool_or(la.origen = 'referido'), false) into v_referido
  from crm.lead_asignaciones la
  where la.lead_id = p_lead_id and la.resultado = 'convertido';

  v_peso := private.peso_referido_conversion(v_periodo);
  v_numerador := case when v_referido then v_peso else 1 end;

  -- Y lo que valia en capital: los contratos que dejan de acreditar, con la
  -- MISMA regla que la cuota. PEN y USD por separado, y ADEMAS desglosado por
  -- categoria: es la casilla exacta de la que habra que descontarlo.
  select
    coalesce(sum(c.capital) filter (where c.moneda = 'PEN'), 0),
    coalesce(sum(c.capital) filter (where c.moneda = 'USD'), 0)
    into v_pen, v_usd
  from private.contratos_afectados_por_anulacion(p_lead_id) x
  join public.contratos c on c.id = x;

  select coalesce(jsonb_agg(jsonb_build_object(
           'categoria', d.categoria, 'moneda', d.moneda,
           'capital', d.capital, 'contratos', d.contratos)), '[]'::jsonb)
    into v_detalle
  from (
    select c.categoria, c.moneda, sum(c.capital) as capital, count(*)::int as contratos
    from private.contratos_afectados_por_anulacion(p_lead_id) x
    join public.contratos c on c.id = x
    group by c.categoria, c.moneda
  ) d;

  -- Un cierre que no valia nada no genera deuda.
  if v_numerador <= 0 and v_pen = 0 and v_usd = 0 then
    return null;
  end if;

  insert into crm.ajustes_mes_cerrado (
    vendedor_id, periodo_origen, lead_id, motivo, creado_por,
    numerador, capital_pen, capital_usd, detalle,
    pendiente_numerador, pendiente_pen, pendiente_usd, pendiente_detalle
  ) values (
    v_acreditado, v_periodo, p_lead_id, p_motivo, p_por,
    v_numerador, v_pen, v_usd, v_detalle,
    v_numerador, v_pen, v_usd, v_detalle
  )
  on conflict (lead_id) do nothing
  returning id into v_id;

  return v_id;
end;
$original$;

do $r$
begin
  if (select md5(prosrc) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='private' and p.proname='registrar_ajuste_si_mes_cerrado')
     <> 'e07c89715b96ee2604ce435fea3e2c34' then
    raise exception '2) La sancion restaurada no da la huella original: ABORTA';
  end if;
  raise notice '2) registrar_ajuste_si_mes_cerrado restaurada (huella verificada)';
end $r$;

-- 3) [182300] Los 9 parches del portal, deshechos por el reemplazo inverso.
--    TAMBIEN antes de tocar es_demo: sus cuerpos la leen.
do $r$
declare v_fn text; v_def text; v_n int := 0;
begin
  for v_fn in select n.nspname||'.'||p.proname
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname in
      ('metricas_directorio','directorio_ranking_analistas','directorio_top_clientes',
       'directorio_morosidad','dashboard_admin_metricas','admin_pagos_metricas',
       'admin_pagos_resumen','pagos_admin_metricas_globales','pagos_admin_resumen_contratos')
      and strpos(p.prosrc, 'WHERE NOT es_demo') > 0
  loop
    select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname||'.'||p.proname = v_fn;
    v_def := replace(v_def, 'FROM (SELECT * FROM contratos WHERE NOT es_demo) contratos', 'FROM contratos');
    v_def := replace(v_def, 'FROM (SELECT * FROM contratos WHERE NOT es_demo) c', 'FROM contratos c');
    v_def := replace(v_def, 'JOIN (SELECT * FROM contratos WHERE NOT es_demo) c ON', 'JOIN contratos c ON');
    execute v_def;
    v_n := v_n + 1;
  end loop;
  raise notice '3) portal: filtro de demos retirado de % funciones', v_n;
end $r$;

-- 4) [182300] marcar_contrato_demo pierde el veto de operaciones (la funcion
--    entera cae en el paso 7, esto es solo por si el 7 se salta a mano).
-- 5) [182200] El nucleo vuelve: fuera la atribucion por analista y el filtro.
do $r$
declare v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p where p.oid = 'private.produccion_mes_por_vendedor(timestamptz,timestamptz,uuid)'::regprocedure;
  if strpos(v_def, 'meta_analista') = 0 then
    raise notice '5) el nucleo no tiene el parche del analista';
  else
    v_def := replace(v_def, E'      c.creado_por,\n      c.analista_cierre_id,', '      c.creado_por,');
    v_def := replace(v_def, 'from (select * from public.contratos where not es_demo) c
', 'from public.contratos c
');
    v_def := regexp_replace(v_def,
      '\n        -- P-055 F3.5b:.*?when base\.analista_cierre_id is not null then meta_analista\.vendedor_id',
      '', 's');
    v_def := regexp_replace(v_def,
      '\n    left join crm\.metas_vendedor meta_analista\n      on meta_analista\.meta_periodo_id=p_periodo_id\n     and meta_analista\.vendedor_id=base\.analista_cierre_id',
      '');
    if strpos(v_def, 'meta_analista') > 0 or strpos(v_def, 'es_demo') > 0 then
      raise exception '5) No se pudo limpiar el nucleo: revisar a mano';
    end if;
    execute v_def;
    if (select md5(prosrc) from pg_proc p
        where p.oid = 'private.produccion_mes_por_vendedor(timestamptz,timestamptz,uuid)'::regprocedure)
       <> '67be8405cbe4cf5df64e7f16409f084a' then
      raise exception '5) El nucleo restaurado no da la huella original: ABORTA';
    end if;
    raise notice '5) produccion_mes_por_vendedor restaurado (huella verificada)';
  end if;
end $r$;

-- 6) [182000] Los 6 parches de metricas del CRM, reemplazo inverso.
do $r$
declare v_fn text; v_def text; v_n int := 0;
begin
  for v_fn in select n.nspname||'.'||p.proname
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname||'.'||p.proname in (
      'crm.contratos_por_periodo_comercial_fn','crm.metricas_capital_mes_fn',
      'crm.metricas_vencimientos_fn','crm.metricas_pagos_mes_fn',
      'crm.resumen_cartera_clientes_fn','private.metricas_conversiones_implementacion')
      and strpos(p.prosrc, 'where not es_demo') > 0
  loop
    select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname||'.'||p.proname = v_fn;
    v_def := replace(v_def, 'from (select * from public.contratos where not es_demo) c'  || E'\n', 'from public.contratos c'  || E'\n');
    v_def := replace(v_def, 'from (select * from public.contratos where not es_demo) ct' || E'\n', 'from public.contratos ct' || E'\n');
    v_def := replace(v_def, 'join (select * from public.contratos where not es_demo) ct  on', 'join public.contratos ct  on');
    execute v_def;
    v_n := v_n + 1;
  end loop;
  raise notice '6) crm: filtro de demos retirado de % funciones', v_n;
end $r$;

-- 7) [182500] La consulta de atribucion.
drop function if exists crm.atribucion_contrato_fn(uuid);

-- 8) [181500] Puertas, candados, rastro (con respaldo en PRIVATE) y el CHECK.
do $r$
declare v_hay bigint; v_nombre text;
begin
  if to_regclass('crm.reasignaciones_analista') is not null then
    select count(*) into v_hay from crm.reasignaciones_analista;
    if v_hay > 0 then
      v_nombre := 'zz_respaldo_reasignaciones_' || to_char(now() at time zone 'America/Lima','YYYYMMDD_HH24MI');
      execute format('create table private.%I as select * from crm.reasignaciones_analista', v_nombre);
      execute format('alter table private.%I enable row level security', v_nombre);
      execute format('revoke all on private.%I from public, anon, authenticated', v_nombre);
      raise warning '8) HABIA % reasignaciones reales: respaldadas en private.%', v_hay, v_nombre;
    end if;
  end if;
end $r$;
drop function if exists public.reasignar_analista_contrato(uuid, uuid, text);
drop function if exists public.marcar_contrato_demo(uuid, boolean, text);
drop trigger if exists trg_contratos_analista_solo_por_la_puerta on public.contratos;
drop trigger if exists trg_contratos_demo_solo_por_la_puerta on public.contratos;
drop trigger if exists trg_contratos_demo_no_nace_marcado on public.contratos;
drop function if exists private.trg_contratos_analista_solo_por_la_puerta();
drop function if exists private.trg_contratos_demo_solo_por_la_puerta();
drop function if exists private.trg_contratos_demo_no_nace_marcado();
drop table if exists crm.reasignaciones_analista;
drop function if exists private.trg_reasignaciones_append_only();

-- El CHECK del registro vuelve a su catalogo original de tres operaciones.
do $r$
begin
  if (select pg_get_constraintdef(oid) from pg_constraint
      where conrelid='public.audit_log'::regclass
        and conname='audit_log_operacion_check') ~ 'demo_marca' then
    -- Si quedaron filas demo_marca, el CHECK viejo no valida filas EXISTENTES
    -- (solo nuevas), pero se declara igual: NOT VALID para no mentir.
    alter table public.audit_log drop constraint audit_log_operacion_check;
    if exists (select 1 from public.audit_log where operacion = 'demo_marca') then
      alter table public.audit_log add constraint audit_log_operacion_check
        check (operacion = any (array['INSERT','UPDATE','DELETE','demo_marca']));
      raise warning '8) Hay filas demo_marca en audit_log: el CHECK conserva el valor para no invalidar historia';
    else
      alter table public.audit_log add constraint audit_log_operacion_check
        check (operacion = any (array['INSERT','UPDATE','DELETE']));
      raise notice '8) CHECK del registro restaurado a tres operaciones';
    end if;
  end if;
end $r$;

-- 9) [180500 + 180000] El relleno cae CON las columnas.
alter table public.contratos
  drop column if exists analista_cierre_id,
  drop column if exists es_demo;

-- 10) Verificacion final: ejecutable de punta a punta.
do $r$
begin
  if exists (select 1 from pg_attribute where attrelid='public.contratos'::regclass
             and attname in ('analista_cierre_id','es_demo') and not attisdropped) then
    raise exception 'MARCHA ATRAS INCOMPLETA: quedan columnas';
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
             where n.nspname in ('public','crm','private')
               and strpos(p.prosrc, 'es_demo') > 0
               and p.proname <> 'log_audit_change') then
    raise exception 'MARCHA ATRAS INCOMPLETA: alguna funcion sigue leyendo es_demo';
  end if;
  raise notice '>>> MARCHA ATRAS F3 COMPLETA Y VERIFICADA <<<';
end $r$;

commit;
