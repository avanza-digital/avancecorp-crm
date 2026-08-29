-- P-055 FASE 4.h — EL MOTOR DEL SELLO consume el nucleo (piezas 1–3 de la
-- lista final de Miguel: «terminemos con la calculadora»).
--
-- QUE CAMBIA:
--   1) private.produccion_mes_por_vendedor — sus DOS fuentes crudas (contratos
--      y cierres_externos) pasan a ser el nucleo, por TRASPLANTE ANCLADO: toda
--      la logica de atribucion (lead explicito → analista → autor, roster,
--      neutralizados por anulacion) queda INTACTA byte a byte; solo cambia de
--      donde salen las filas.
--   2) crm.cerrar_periodo — SIN CAMBIO DE CUERPO: su capital ya es derivado de
--      produccion, asi que queda alimentada por transitividad (se declara).
--   3) private.registrar_ajuste_si_mes_cerrado — su rama de CONTRATOS pasa al
--      nucleo. Su rama de COOPERATIVA ANULADA se queda cruda A PROPOSITO y
--      queda escrito por que: el nucleo carga el capital QUE EXISTE (una
--      anulada aporta 0 por la decision 15); la deuda necesita el monto
--      ORIGINAL de lo anulado. Leer eso del registro de cierres no es una
--      calculadora paralela: es la unica fuente del hecho "cuanto valia".
--
-- EL JUEZ ES EL ENSAYO DEL CIERRE: fuera de esta migracion, el cierre completo
-- de agosto se ensayo con el motor VIEJO y con el NUEVO (tecnica del clon con
-- el calendario movido) y la foto sellada tiene que ser IDENTICA. Ademas esta
-- migracion trae su oraculo interno: produccion() de agosto y de todo-el-rango
-- byte a byte, y el payload entero de metricas_vendedores_fn (que deriva del
-- motor) fotografiado antes/despues.

begin;

set local lock_timeout = '5s';

create temp table zz_f4h (k text, h text) on commit drop;

do $antes$
declare v_uid uuid := 'bf1c562e-ed08-4cc3-92a8-34f1fa3e9127';
        v_meta uuid; h1 text; h2 text; h3 text;
begin
  select id into v_meta from crm.meta_periodos where periodo=date '2026-08-01'
  order by revision desc limit 1;
  select md5(coalesce(jsonb_agg(to_jsonb(t) order by t.vendedor_id, t.categoria, t.moneda)::text,'[]'))
    into h1
  from private.produccion_mes_por_vendedor(
    (date '2026-08-01')::timestamp at time zone 'America/Lima',
    (date '2026-09-01')::timestamp at time zone 'America/Lima', v_meta) t;
  select md5(coalesce(jsonb_agg(to_jsonb(t) order by t.vendedor_id, t.categoria, t.moneda)::text,'[]'))
    into h2
  from private.produccion_mes_por_vendedor(
    (date '2026-06-01')::timestamp at time zone 'America/Lima',
    (date '2026-09-01')::timestamp at time zone 'America/Lima', v_meta) t;

  execute format('set local request.jwt.claims = %L',
    json_build_object('sub', v_uid, 'role','authenticated')::text);
  set local role authenticated;
  select md5((crm.metricas_vendedores_fn() - 'generado_en')::text) into h3;
  reset role;

  insert into zz_f4h values ('prod_ago',h1), ('prod_rango',h2), ('vendedores',h3);
end
$antes$;

-- ---------------------------------------------------------- LOS TRASPLANTES --
do $parche$
declare
  v_src text; v_nuevo text; v_h text;
  a1 text; r1 text; a2 text; r2 text;
begin
  select p.prosrc, md5(p.prosrc) into v_src, v_h from pg_proc p
  where p.oid='private.produccion_mes_por_vendedor(timestamptz,timestamptz,uuid)'::regprocedure;
  if v_h <> '1a2609f888962f4ed8201cf9d5bbdb33' then
    raise exception 'produccion cambio (huella %): ABORTA', v_h;
  end if;

  -- fuente 1: contratos → nucleo (misma ventana; expone las MISMAS columnas)
  a1 := '    from (select * from public.contratos where not es_demo) c
';
  r1 := '    from (select k.contrato_id as id, k.categoria, k.moneda,
                 k.monto as capital, k.registrado_por as creado_por,
                 k.analista_id as analista_cierre_id,
                 (k.fecha at time zone ''America/Lima'')::date as fecha_cierre_comercial
          from private.capital_episodios(p_ini, p_fin, true, ''{}''::uuid[]) k
          where k.tipo like ''contrato_%'' and k.medida = ''stock'') c
';
  -- fuente 2: cooperativas → nucleo (vigentes; la ventana ya viene del nucleo)
  a2 := '    from crm.cierres_externos ce
    join crm.metas_vendedor mv
      on mv.meta_periodo_id=p_periodo_id
     and mv.vendedor_id=ce.vendedor_id
    where ce.creado_en>=p_ini and ce.creado_en<p_fin';
  r2 := '    from (select k.cierre_externo_id as id, k.analista_id as vendedor_id,
                 k.moneda, k.monto, k.anulado,
                 k.fecha as creado_en
          from private.capital_episodios(p_ini, p_fin, true, ''{}''::uuid[]) k
          where k.tipo = ''cooperativa'') ce
    join crm.metas_vendedor mv
      on mv.meta_periodo_id=p_periodo_id
     and mv.vendedor_id=ce.vendedor_id
    where ce.creado_en>=p_ini and ce.creado_en<p_fin';

  if (length(v_src)-length(replace(v_src,a1,'')))/length(a1) <> 1
   or (length(v_src)-length(replace(v_src,a2,'')))/length(a2) <> 1 then
    raise exception 'Las anclas del motor no aparecen exactamente una vez: ABORTA';
  end if;

  v_nuevo := replace(v_src, a1, r1);
  v_nuevo := replace(v_nuevo, a2, r2);
  -- la condicion de anulado del leg viejo era `ce.anulado_en is null`:
  if (length(v_nuevo)-length(replace(v_nuevo,'      and ce.anulado_en is null','')))/length('      and ce.anulado_en is null') <> 1 then
    raise exception 'El ancla de anulado no aparece exactamente una vez: ABORTA';
  end if;
  v_nuevo := replace(v_nuevo, '      and ce.anulado_en is null', '      and not ce.anulado');
  -- y el leg viejo leia ce.monto como capital:
  if (length(v_nuevo)-length(replace(v_nuevo,'ce.monto as capital','')))/length('ce.monto as capital') <> 1 then
    raise exception 'El ancla del monto no aparece exactamente una vez: ABORTA';
  end if;

  execute format(
    'create or replace function private.produccion_mes_por_vendedor('
    'p_ini timestamptz, p_fin timestamptz, p_periodo_id uuid) '
    'returns table(vendedor_id uuid, categoria text, moneda text, contratos_real integer, capital_real numeric) '
    'language sql stable security definer set search_path to '''' as %L', v_nuevo);

  -- registrar_ajuste: la rama de contratos, al nucleo
  select p.prosrc, md5(p.prosrc) into v_src, v_h from pg_proc p
  where p.oid='private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)'::regprocedure;
  if v_h <> '329e0ae5abc548d88ca97e631031dbe5' then
    raise exception 'registrar_ajuste cambio (huella %): ABORTA', v_h;
  end if;

  a1 := '    select c.categoria::text as categoria, c.moneda::text as moneda, c.capital as capital
    from private.contratos_afectados_por_anulacion(p_lead_id) x
    join public.contratos c on c.id = x and not c.es_demo';
  r1 := '    select k.categoria::text as categoria, k.moneda::text as moneda, k.monto as capital
    from private.contratos_afectados_por_anulacion(p_lead_id) x
    join private.capital_episodios(''-infinity''::timestamptz, ''infinity''::timestamptz,
                                   true, ''{}''::uuid[]) k
      on k.contrato_id = x and k.tipo like ''contrato_%'' and k.medida = ''stock''';
  if (length(v_src)-length(replace(v_src,a1,'')))/length(a1) <> 1 then
    raise exception 'El ancla de la deuda no aparece exactamente una vez: ABORTA';
  end if;
  v_nuevo := replace(v_src, a1, r1);

  execute format(
    'create or replace function private.registrar_ajuste_si_mes_cerrado('
    'p_lead_id uuid, p_motivo text, p_por uuid) returns uuid '
    'language plpgsql security definer set search_path to '''' as %L', v_nuevo);
end
$parche$;

-- ------------------------------------------------------------------ ORACULO --
do $despues$
declare v_uid uuid := 'bf1c562e-ed08-4cc3-92a8-34f1fa3e9127';
        v_meta uuid; h1 text; h2 text; h3 text; v_falla text := '';
begin
  select id into v_meta from crm.meta_periodos where periodo=date '2026-08-01'
  order by revision desc limit 1;
  select md5(coalesce(jsonb_agg(to_jsonb(t) order by t.vendedor_id, t.categoria, t.moneda)::text,'[]'))
    into h1
  from private.produccion_mes_por_vendedor(
    (date '2026-08-01')::timestamp at time zone 'America/Lima',
    (date '2026-09-01')::timestamp at time zone 'America/Lima', v_meta) t;
  select md5(coalesce(jsonb_agg(to_jsonb(t) order by t.vendedor_id, t.categoria, t.moneda)::text,'[]'))
    into h2
  from private.produccion_mes_por_vendedor(
    (date '2026-06-01')::timestamp at time zone 'America/Lima',
    (date '2026-09-01')::timestamp at time zone 'America/Lima', v_meta) t;

  execute format('set local request.jwt.claims = %L',
    json_build_object('sub', v_uid, 'role','authenticated')::text);
  set local role authenticated;
  select md5((crm.metricas_vendedores_fn() - 'generado_en')::text) into h3;
  reset role;

  if h1 <> (select h from zz_f4h where k='prod_ago')   then v_falla := v_falla || 'produccion/agosto '; end if;
  if h2 <> (select h from zz_f4h where k='prod_rango') then v_falla := v_falla || 'produccion/rango '; end if;
  if h3 <> (select h from zz_f4h where k='vendedores') then v_falla := v_falla || 'vendedores/punta-a-punta '; end if;

  if v_falla <> '' then
    raise exception 'ORACULO F4.h: el motor cambio el resultado en [%]: NO se publica', v_falla;
  end if;
  raise notice 'ORACULO F4.h OK: el motor da byte a byte lo mismo, y vendedores tambien';
end
$despues$;

commit;
