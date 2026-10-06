-- B11 · Suite de comportamiento (banco LOCAL de Docker; termina en ROLLBACK, no deja nada).
--
-- Fabrica, sobre un cierre REAL de octubre (una acreditación de un lead landing), dos clones: un contacto de base cargada y
-- un lead de origen «otro», cada uno con su episodio y su acreditación, y mide el ANTES y el DESPUÉS en todas las piezas que
-- tocó B11. Los clones se insertan con session_replication_role = replica (solo un superusuario: en producción no corre).
--   S1 · base cargada: numerador +1, divisor +0, cierres +1 (mensual, Rendimiento, Equipo, Distribución, Inteligencia
--        comercial, Divisor de coordinación con su columna nueva y su clave nueva), «otros» +0, las partes suman el bruto en
--        cada fila, las sondas de paridad de Equipo y Distribución siguen cuadrando y la de «cierre sin episodio» lo ve.
--   S2 · origen «otro» (control): numerador +0, cierres +0, «otros» +1.
--   S3 · mes sellado: el ajuste de un cierre de base anulado pesa 1 (registrar_ajuste_si_mes_cerrado); el de «otro», nada.
-- Uso (superusuario del stack local): psql -h 127.0.0.1 -p <puerto> -U supabase_admin -X -f supabase/scripts/base-gestion/b11-conversion.sql

begin;
set local search_path = '';

do $suite$
declare
  v_ger uuid;
  v_mes constant date := pg_catalog.date_trunc('month', pg_catalog.now() at time zone 'America/Lima')::date;
  v_fin_mes date;
  v_hoy date := (pg_catalog.now() at time zone 'America/Lima')::date;
  v_ini timestamptz;
  v_fin timestamptz;
  v_peso numeric;
  t record;               -- la acreditación plantilla
  v_x uuid;               -- el analista que cierra
  v_base uuid := gen_random_uuid();
  v_otro uuid := gen_random_uuid();
  v_n integer := 0;
  a0 record; a1 record; a2 record;   -- conversión mensual por vendedor de X
  d0 record; d1 record; d2 record;   -- divisor de empresa de X
  t0 record; t1 record; t2 record;   -- totales de empresa
  c0 jsonb; c1 jsonb; c2 jsonb;      -- Divisor de coordinación
  i0 jsonb; i1 jsonb; i2 jsonb;      -- Inteligencia comercial
  e0 jsonb; e1 jsonb; e2 jsonb;      -- Equipo
  r0 jsonb; r1 jsonb;                -- Distribución
  v_huerfano uuid := gen_random_uuid();
  m1 jsonb;                          -- conversión mensual sin cartera
  v_ajuste uuid;
  v_aj_num numeric;

begin
  v_fin_mes := (v_mes + interval '1 month' - interval '1 day')::date;
  v_ini := v_mes::timestamp at time zone 'America/Lima';
  v_fin := (v_mes + interval '1 month')::timestamp at time zone 'America/Lima';
  v_peso := private.peso_referido_conversion(v_mes);

  if pg_catalog.current_setting('is_superuser') <> 'on' then
    raise exception 'NOT RUN: la suite fabrica datos con replication_role y solo corre en un banco local';
  end if;
  select e.perfil_id into v_ger from crm.equipo e where private.rol_crm(e.perfil_id) = 'gerencia' order by e.perfil_id limit 1;
  perform pg_catalog.set_config('request.jwt.claims', pg_catalog.json_build_object('sub', v_ger, 'role', 'authenticated')::text, true);
  perform pg_catalog.set_config('request.jwt.claim.sub', v_ger::text, true);

  select ca.* into t from crm.conversion_acreditaciones ca join crm.leads l on l.id = ca.lead_id
   where ca.estado = 'acreditada' and ca.periodo_comercial = v_mes and l.origen in ('landing', 'formulario')
     and ca.analista_id is not null and not private.cierre_externo_anulado(ca.lead_id)
   order by ca.fecha_comercial, ca.id limit 1;
  if t.id is null then raise exception 'NOT RUN: no hay un cierre landing/formulario acreditado este mes para clonar'; end if;
  v_x := t.analista_id;

  -- ── ANTES ──
  select * into a0 from private.conversion_mensual_por_vendedor(v_ini, v_fin, true, null::uuid[], v_peso) r where r.analista_id = v_x;
  select * into d0 from private.conversion_divisor_empresa(v_mes, v_fin_mes) r where r.analista_id = v_x;
  select * into t0 from private.conversion_divisor_empresa_totales(v_mes, v_fin_mes);
  c0 := crm.conversion_divisor_coordinacion_fn(v_mes, null, null);
  i0 := private.metricas_conversiones_implementacion(v_mes, v_hoy, null);
  e0 := crm.metricas_conversiones_equipo_fn(v_mes, v_hoy);
  r0 := private.metricas_distribucion_leads_v3_core(v_mes, v_hoy, pg_catalog.now());

  -- ── Clones (base y «otro»): lead, episodio y acreditación copiados de la plantilla ──
  set local session_replication_role = replica;
  execute (select pg_catalog.format('insert into crm.leads (%1$s) select %1$s from pg_catalog.jsonb_populate_record(null::crm.leads, $1)',
                  pg_catalog.string_agg(pg_catalog.quote_ident(a.attname), ', ' order by a.attnum))
             from pg_attribute a where a.attrelid = 'crm.leads'::regclass and a.attnum > 0 and not a.attisdropped and a.attgenerated = '')
    using (select pg_catalog.to_jsonb(l) || pg_catalog.jsonb_build_object('id', v_base, 'origen', 'base_cargada', 'telefono', '999' || pg_catalog.lpad((pg_catalog.random() * 999999)::int::text, 6, '0'),
                  'dni', null, 'inversionista_id', null) from crm.leads l where l.id = t.lead_id);
  execute (select pg_catalog.format('insert into crm.leads (%1$s) select %1$s from pg_catalog.jsonb_populate_record(null::crm.leads, $1)',
                  pg_catalog.string_agg(pg_catalog.quote_ident(a.attname), ', ' order by a.attnum))
             from pg_attribute a where a.attrelid = 'crm.leads'::regclass and a.attnum > 0 and not a.attisdropped and a.attgenerated = '')
    using (select pg_catalog.to_jsonb(l) || pg_catalog.jsonb_build_object('id', v_otro, 'origen', 'otro', 'telefono', '998' || pg_catalog.lpad((pg_catalog.random() * 999999)::int::text, 6, '0'),
                  'dni', null, 'inversionista_id', null) from crm.leads l where l.id = t.lead_id);
  -- Cada clon necesita su fuente ELEGIBLE (private.conversion_exclusion_fuente): un cierre externo inicial propio, copiado
  -- de uno vivo del banco.
  create temporary table b11_ep (lead_id uuid, episodio uuid, fuente uuid) on commit drop;
  insert into b11_ep values (v_base, gen_random_uuid(), gen_random_uuid()), (v_otro, gen_random_uuid(), gen_random_uuid());
  insert into crm.cierres_externos
    select (pg_catalog.jsonb_populate_record(null::crm.cierres_externos, pg_catalog.to_jsonb(ce)
      || pg_catalog.jsonb_build_object('id', b.fuente, 'lead_id', b.lead_id, 'es_cierre_inicial', true,
                                       'numero_transaccion', 'B11-' || b.fuente::text))).*
      from b11_ep b
      cross join lateral (select ce0.* from crm.cierres_externos ce0 where ce0.es_cierre_inicial
                           and private.conversion_exclusion_fuente('cierre_externo', ce0.id) = 'elegible'
                           and not private.cierre_externo_anulado(ce0.lead_id) order by ce0.id limit 1) ce;
  if (select count(*) from crm.cierres_externos where id in (select fuente from b11_ep)) <> 2 then
    raise exception 'NOT RUN: no hay un cierre externo inicial vivo para copiar como fuente';
  end if;
  execute (select pg_catalog.format('insert into crm.lead_asignaciones (%1$s) select %1$s from pg_catalog.jsonb_populate_record(null::crm.lead_asignaciones, $1)',
                  pg_catalog.string_agg(pg_catalog.quote_ident(a.attname), ', ' order by a.attnum))
             from pg_attribute a where a.attrelid = 'crm.lead_asignaciones'::regclass and a.attnum > 0 and not a.attisdropped and a.attgenerated = '')
    using (select pg_catalog.to_jsonb(la) || pg_catalog.jsonb_build_object('id', (select episodio from b11_ep where lead_id = v_base), 'lead_id', v_base)
             from crm.lead_asignaciones la where la.id = t.episodio_id);
  execute (select pg_catalog.format('insert into crm.lead_asignaciones (%1$s) select %1$s from pg_catalog.jsonb_populate_record(null::crm.lead_asignaciones, $1)',
                  pg_catalog.string_agg(pg_catalog.quote_ident(a.attname), ', ' order by a.attnum))
             from pg_attribute a where a.attrelid = 'crm.lead_asignaciones'::regclass and a.attnum > 0 and not a.attisdropped and a.attgenerated = '')
    using (select pg_catalog.to_jsonb(la) || pg_catalog.jsonb_build_object('id', (select episodio from b11_ep where lead_id = v_otro), 'lead_id', v_otro)
             from crm.lead_asignaciones la where la.id = t.episodio_id);
  insert into crm.conversion_acreditaciones
    select (pg_catalog.jsonb_populate_record(null::crm.conversion_acreditaciones, pg_catalog.to_jsonb(t)
      || pg_catalog.jsonb_build_object('id', gen_random_uuid(), 'lead_id', v_base, 'episodio_id', (select episodio from b11_ep where lead_id = v_base),
                                       'fuente_tipo', 'cierre_externo', 'fuente_id', (select fuente from b11_ep where lead_id = v_base),
                                       'origen', 'base_cargada', 'inversionista_id', null))).*;
  set local session_replication_role = origin;

  -- ── S1 · un cierre de base cargada ──
  select * into a1 from private.conversion_mensual_por_vendedor(v_ini, v_fin, true, null::uuid[], v_peso) r where r.analista_id = v_x;
  select * into d1 from private.conversion_divisor_empresa(v_mes, v_fin_mes) r where r.analista_id = v_x;
  select * into t1 from private.conversion_divisor_empresa_totales(v_mes, v_fin_mes);
  c1 := crm.conversion_divisor_coordinacion_fn(v_mes, null, null);
  i1 := private.metricas_conversiones_implementacion(v_mes, v_hoy, null);
  e1 := crm.metricas_conversiones_equipo_fn(v_mes, v_hoy);
  m1 := crm.conversion_mensual_sin_cartera_fn(v_mes);
  r1 := private.metricas_distribucion_leads_v3_core(v_mes, v_hoy, pg_catalog.now());

  if a1.numerador is distinct from a0.numerador + 1 then raise exception 'S1.1 mensual: numerador % → % (esperado +1)', a0.numerador, a1.numerador; end if; v_n := v_n + 1;
  if a1.divisor is distinct from a0.divisor then raise exception 'S1.2 mensual: el divisor se movió % → %', a0.divisor, a1.divisor; end if; v_n := v_n + 1;
  if a1.cierres_no_referidos is distinct from a0.cierres_no_referidos + 1 then raise exception 'S1.3 mensual: cierres_no_referidos % → %', a0.cierres_no_referidos, a1.cierres_no_referidos; end if; v_n := v_n + 1;
  if (select sum((p ->> 'cierres')::int) from pg_catalog.jsonb_array_elements(a1.procedencia) p) is distinct from a1.cierres_no_referidos + a1.cierres_referidos then
    raise exception 'S1.4 mensual: la procedencia no suma los cierres (el front lo rechaza)'; end if; v_n := v_n + 1;
  if exists (select 1 from private.conversion_episodios(v_ini, v_fin, v_mes, true, null::uuid[], v_peso) e where e.lead_id = v_base and e.tipo = 'recibido') then
    raise exception 'S1.5 el contacto de base apareció como llegada'; end if; v_n := v_n + 1;
  if d1.cierres_base_cargada is distinct from coalesce(d0.cierres_base_cargada, 0) + 1 or d1.cierres_otros is distinct from d0.cierres_otros
     or d1.numerador_bruto is distinct from d0.numerador_bruto + 1 or d1.divisor is distinct from d0.divisor then
    raise exception 'S1.6 divisor de empresa: base % → %, otros % → %, bruto % → %', d0.cierres_base_cargada, d1.cierres_base_cargada, d0.cierres_otros, d1.cierres_otros, d0.numerador_bruto, d1.numerador_bruto; end if; v_n := v_n + 1;
  if exists (select 1 from private.conversion_divisor_empresa(v_mes, v_fin_mes) f where f.desglose_disponible
               and abs(f.cierres_formulario + f.cierres_landing + f.cierres_base_cargada + f.cierres_referido_aporte + f.upgrade + f.renovacion_aporte - f.numerador_bruto) > 0.000001) then
    raise exception 'S1.7 divisor de empresa: las partes no suman el bruto'; end if; v_n := v_n + 1;
  if t1.cierres_base_cargada is distinct from coalesce(t0.cierres_base_cargada, 0) + 1 or t1.numerador_bruto is distinct from t0.numerador_bruto + 1 then
    raise exception 'S1.8 totales: base % → %', t0.cierres_base_cargada, t1.cierres_base_cargada; end if; v_n := v_n + 1;
  if (c1 #>> '{empresa,cierres,base_cargada}')::int is distinct from coalesce((c0 #>> '{empresa,cierres,base_cargada}')::int, 0) + 1
     or (select (a ->> 'cierres')::jsonb ->> 'base_cargada' from pg_catalog.jsonb_array_elements(c1 -> 'analistas') a where (a ->> 'analista_id')::uuid = v_x)::int
        is distinct from coalesce((select (a ->> 'cierres')::jsonb ->> 'base_cargada' from pg_catalog.jsonb_array_elements(c0 -> 'analistas') a where (a ->> 'analista_id')::uuid = v_x)::int, 0) + 1 then
    raise exception 'S1.9 coordinación: la clave base_cargada no subió en 1'; end if; v_n := v_n + 1;
  if (i1 #>> '{nucleo,numerador}')::numeric is distinct from (i0 #>> '{nucleo,numerador}')::numeric + 1
     or (i1 #>> '{nucleo,cierres_no_referidos}')::int is distinct from (i0 #>> '{nucleo,cierres_no_referidos}')::int + 1
     or (i1 #>> '{nucleo,divisor}')::int is distinct from (i0 #>> '{nucleo,divisor}')::int then
    raise exception 'S1.10 Inteligencia comercial: núcleo % → %', i0 -> 'nucleo', i1 -> 'nucleo'; end if; v_n := v_n + 1;
  if (select sum((s ->> 'aporte_cierres')::numeric) from pg_catalog.jsonb_array_elements(i1 -> 'responsables') r, pg_catalog.jsonb_array_elements(r -> 'cierres_por_semana') s
       where (r ->> 'vendedor_id')::uuid = v_x)
     is distinct from (select sum((s ->> 'aporte_cierres')::numeric) from pg_catalog.jsonb_array_elements(i0 -> 'responsables') r, pg_catalog.jsonb_array_elements(r -> 'cierres_por_semana') s
       where (r ->> 'vendedor_id')::uuid = v_x) + 1 then
    raise exception 'S1.11 Inteligencia comercial: el aporte semanal de X no subió en 1'; end if; v_n := v_n + 1;
  if (e1 #>> '{sondas,cuadra}')::boolean is not true
     or (select (r ->> 'nucleo_numerador')::numeric from pg_catalog.jsonb_array_elements(e1 -> 'responsables') r where (r ->> 'vendedor_id')::uuid = v_x)
        is distinct from (select (r ->> 'nucleo_numerador')::numeric from pg_catalog.jsonb_array_elements(e0 -> 'responsables') r where (r ->> 'vendedor_id')::uuid = v_x) + 1 then
    raise exception 'S1.12 Equipo: sonda % o numerador de X sin el +1', e1 #> '{sondas}'; end if; v_n := v_n + 1;
  if m1::text not like '%"cierres_sin_episodio": 0%' then
    raise exception 'S1.13 conversión mensual: la sonda ve un cierre sin episodio (%)', m1 -> 'cobertura'; end if; v_n := v_n + 1;
  if (r1 #>> '{sondas,cuadra}')::boolean is not true or (r1 #>> '{sondas,paridad_nucleo}')::numeric <> 0
     or pg_catalog.jsonb_path_query_first(r1, '$.*.nucleo_numerador')::text::numeric
        is distinct from pg_catalog.jsonb_path_query_first(r0, '$.*.nucleo_numerador')::text::numeric + 1 then
    raise exception 'S1.14 Distribución: sondas % o numerador sin el +1', r1 -> 'sondas'; end if; v_n := v_n + 1;
  -- Un contacto de base convertido SIN episodio es lo que la sonda debe ver (la lista vieja no lo miraba).
  set local session_replication_role = replica;
  execute (select pg_catalog.format('insert into crm.leads (%1$s) select %1$s from pg_catalog.jsonb_populate_record(null::crm.leads, $1)',
                  pg_catalog.string_agg(pg_catalog.quote_ident(a.attname), ', ' order by a.attnum))
             from pg_attribute a where a.attrelid = 'crm.leads'::regclass and a.attnum > 0 and not a.attisdropped and a.attgenerated = '')
    using (select pg_catalog.to_jsonb(l) || pg_catalog.jsonb_build_object('id', v_huerfano, 'origen', 'base_cargada', 'etapa', 'convertido',
                  'convertido_en', t.acreditado_en, 'telefono', '997' || pg_catalog.lpad((pg_catalog.random() * 999999)::int::text, 6, '0'),
                  'dni', null, 'inversionista_id', null) from crm.leads l where l.id = t.lead_id);
  set local session_replication_role = origin;
  if crm.conversion_mensual_sin_cartera_fn(v_mes)::text not like '%"cierres_sin_episodio": 1%' then
    raise exception 'S1.15 la sonda no ve el cierre de base sin episodio'; end if; v_n := v_n + 1;
  set local session_replication_role = replica;
  delete from crm.leads where id = v_huerfano;
  set local session_replication_role = origin;

  -- ── S2 · control: un cierre de origen «otro» no pesa ──
  set local session_replication_role = replica;
  insert into crm.conversion_acreditaciones
    select (pg_catalog.jsonb_populate_record(null::crm.conversion_acreditaciones, pg_catalog.to_jsonb(t)
      || pg_catalog.jsonb_build_object('id', gen_random_uuid(), 'lead_id', v_otro, 'episodio_id', (select episodio from b11_ep where lead_id = v_otro),
                                       'fuente_tipo', 'cierre_externo', 'fuente_id', (select fuente from b11_ep where lead_id = v_otro),
                                       'origen', 'otro', 'inversionista_id', null))).*;
  set local session_replication_role = origin;
  select * into a2 from private.conversion_mensual_por_vendedor(v_ini, v_fin, true, null::uuid[], v_peso) r where r.analista_id = v_x;
  select * into d2 from private.conversion_divisor_empresa(v_mes, v_fin_mes) r where r.analista_id = v_x;
  if a2.numerador is distinct from a1.numerador or a2.cierres_no_referidos is distinct from a1.cierres_no_referidos then
    raise exception 'S2.1 un cierre «otro» movió la conversión: % → %', a1.numerador, a2.numerador; end if; v_n := v_n + 1;
  if d2.cierres_otros is distinct from d1.cierres_otros + 1 or d2.cierres_base_cargada is distinct from d1.cierres_base_cargada
     or d2.numerador_bruto is distinct from d1.numerador_bruto then
    raise exception 'S2.2 divisor de empresa con «otro»: otros % → %, base % → %', d1.cierres_otros, d2.cierres_otros, d1.cierres_base_cargada, d2.cierres_base_cargada; end if; v_n := v_n + 1;
  if private.conversion_origen_con_cierre('oficina') or private.conversion_origen_con_cierre('otro') then
    raise exception 'S2.3 el ayudante cuenta oficina u otro'; end if; v_n := v_n + 1;

  -- ── S3 · mes sellado: el ajuste de un cierre de base pesa 1 ──
  set local session_replication_role = replica;
  insert into crm.periodos_cerrados (periodo, ponderacion_referido, meta_revision, cobertura) values (v_mes, v_peso, 0, '{}'::jsonb);
  -- Una foto por persona CON desglose (origenes_ranking disponible y cartera), para que la rama sellada devuelva filas.
  insert into crm.cierre_mes_vendedor (periodo, vendedor_id, nombre_completo, supervisor_id, supervisor_nombre, divisor,
      cierres_no_referidos, cierres_referidos, cierres_de_arrastre, numerador, estado, referidos_recibidos, referidos_dados_de_alta,
      conversion_objetivo, origenes_ranking)
    values (v_mes, v_x, 'FOTO B11', v_ger, 'SUPERVISION B11', 1, 2, 0, 0, 2, 'medible', 0, 0, 0,
      '{"disponible": true, "filas": [{"origen": "landing", "cierres": 1}]}'::jsonb);
  update crm.conversion_acreditaciones set incluida_en_sello = true, sellado_en = pg_catalog.now() where lead_id in (v_base, v_otro);
  update crm.leads set convertido_en = coalesce(convertido_en, t.acreditado_en) where id in (v_base, v_otro);
  set local session_replication_role = origin;
  -- La sección del divisor de un mes SELLADO no tiene la base en la foto: NULL, nunca un 0 inventado.
  if not exists (select 1 from private.conversion_divisor_empresa(v_mes, v_fin_mes) f where f.analista_id = v_x and f.desglose_disponible)
     or exists (select 1 from private.conversion_divisor_empresa(v_mes, v_fin_mes) f where f.cierres_base_cargada is not null) then
    raise exception 'S3.1 mes sellado: cierres_base_cargada debería ser NULL'; end if; v_n := v_n + 1;
  if (select r.desglose_disponible from private.conversion_divisor_empresa_totales(v_mes, v_fin_mes) r) is not true
     or (select r.cierres_base_cargada from private.conversion_divisor_empresa_totales(v_mes, v_fin_mes) r) is not null then
    raise exception 'S3.2 mes sellado: el total de base debería ser NULL'; end if; v_n := v_n + 1;
  v_ajuste := private.registrar_ajuste_si_mes_cerrado(v_base, 'prueba B11 base cargada', v_ger);
  if v_ajuste is null then raise exception 'S3.3 el cierre de base anulado en un mes sellado no generó ajuste'; end if; v_n := v_n + 1;
  select a.numerador into v_aj_num from crm.ajustes_mes_cerrado a where a.id = v_ajuste;
  if v_aj_num is distinct from 1 then raise exception 'S3.4 el ajuste de base pesa % (esperado 1)', v_aj_num; end if; v_n := v_n + 1;
  if private.registrar_ajuste_si_mes_cerrado(v_otro, 'prueba B11 otro', v_ger) is not null then
    raise exception 'S3.5 el cierre «otro» generó ajuste'; end if; v_n := v_n + 1;

  raise notice 'B11 suite: PASS % de % (analista %, plantilla %)', v_n, 23, v_x, t.lead_id;
  if v_n <> 23 then raise exception 'B11 suite: faltan casos (% de 23)', v_n; end if;
end;
$suite$;

rollback;
