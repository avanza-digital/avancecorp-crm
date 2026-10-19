-- REVERSA de 20261019170422_crm_gestion_diaria_llamadas_clientes.sql
-- Devuelve el lector y el agregador a sus cuerpos de producción del 19/10/2026 (copiados byte a byte del
-- volcado vivo), deshace los tres reemplazos anclados del gate (compone con otros re-sellados del mismo gate) y
-- retira el ayudante y los mutantes. No borra datos: la migración no escribe filas.
begin;
set local lock_timeout = '5s';
set local quote_all_identifiers = off;

do $reversa$
declare
  v_def text;
  v_seccion text;
  v_md5_ayudante text;
  v_md5_lector text;
  v_md5_agregador text;
begin
  if to_regprocedure('private.gestion_diaria_llamadas_clientes_eventos(timestamptz,timestamptz,uuid[])') is null then
    raise exception 'REVERSA llamadas_clientes: no esta instalada';
  end if;
  v_md5_ayudante := md5(pg_get_functiondef('private.gestion_diaria_llamadas_clientes_eventos(timestamptz,timestamptz,uuid[])'::regprocedure));
  v_md5_lector := md5(pg_get_functiondef('private.gestion_diaria_llamadas_eventos(timestamptz,timestamptz,uuid[])'::regprocedure));
  v_md5_agregador := md5(pg_get_functiondef('private.gestion_diaria_llamadas(timestamptz,timestamptz,uuid[])'::regprocedure));
  -- No se pisa a ciegas: lo instalado debe ser EXACTAMENTE lo de 20261019170422 (huellas selladas en el ensayo).
  if v_md5_ayudante <> '35c22cec66e3f7fa929d1514c338e3b3' or v_md5_lector <> 'a209ec1be82b2eeff40c7f6488342d69'
     or v_md5_agregador <> '231845001abb2386645231442a5fb103' then
    raise exception 'REVERSA llamadas_clientes: lo instalado no es lo de 20261019170422 (ayudante %, lector %, agregador %): revisar antes de revertir',
      v_md5_ayudante, v_md5_lector, v_md5_agregador;
  end if;

  -- 1. El gate: quitar la sección 2b y devolver las dos huellas de producción.
  v_def := pg_get_functiondef('private.assert_gestion_diaria_analista()'::regprocedure);
  v_seccion := substring(v_def from '  -- 1b\. El ayudante DEFINER de las llamadas a CLIENTES.*?\n\n(?=  -- 2\. Los CUERPOS propios, sellados)');
  if v_seccion is null then
    raise exception 'REVERSA llamadas_clientes: el gate no trae la seccion 1b con su ancla';
  end if;
  v_def := replace(v_def, v_seccion, '');
  v_def := replace(v_def, '''' || v_md5_agregador || '''', '''7c5d14e65cc0e55e57214589d11e9c9d''');
  v_def := replace(v_def, '''' || v_md5_lector || '''', '''27d25609c74e04c58f82e36af45d7327''');
  -- Primera pasada del ensayo (gate instalado con marcadores provisionales): también se devuelven.
  v_def := replace(v_def, '''MD5_AGREGADOR_PENDIENTE_0000000000''', '''7c5d14e65cc0e55e57214589d11e9c9d''');
  v_def := replace(v_def, '''MD5_LECTOR_PENDIENTE_000000000000''', '''27d25609c74e04c58f82e36af45d7327''');
  if v_def like '%gestion_diaria_llamadas_clientes_eventos%' then
    raise exception 'REVERSA llamadas_clientes: el gate sigue nombrando al ayudante';
  end if;
  execute v_def;
  -- Los gates de citas y del pulso: devolver las huellas de producción (también los marcadores de la primera pasada).
  v_def := pg_get_functiondef('private.assert_gestion_diaria_citas()'::regprocedure);
  if strpos(v_def, '''' || v_md5_agregador || '''') = 0 and strpos(v_def, '''MD5_AGREGADOR_PENDIENTE_0000000000''') = 0 then
    raise exception 'REVERSA llamadas_clientes: el gate de citas no trae la huella instalada del agregador';
  end if;
  v_def := replace(v_def, '''' || v_md5_agregador || '''', '''7c5d14e65cc0e55e57214589d11e9c9d''');
  v_def := replace(v_def, '''MD5_AGREGADOR_PENDIENTE_0000000000''', '''7c5d14e65cc0e55e57214589d11e9c9d''');
  execute v_def;
  v_def := pg_get_functiondef('private.assert_gestion_diaria_pulso()'::regprocedure);
  if (strpos(v_def, '''' || v_md5_agregador || '''') = 0 and strpos(v_def, '''MD5_AGREGADOR_PENDIENTE_0000000000''') = 0)
     or (strpos(v_def, '''' || v_md5_lector || '''') = 0 and strpos(v_def, '''MD5_LECTOR_PENDIENTE_000000000000''') = 0) then
    raise exception 'REVERSA llamadas_clientes: el gate del pulso no trae las huellas instaladas';
  end if;
  v_def := replace(v_def, '''' || v_md5_agregador || '''', '''7c5d14e65cc0e55e57214589d11e9c9d''');
  v_def := replace(v_def, '''' || v_md5_lector || '''', '''27d25609c74e04c58f82e36af45d7327''');
  v_def := replace(v_def, '''MD5_AGREGADOR_PENDIENTE_0000000000''', '''7c5d14e65cc0e55e57214589d11e9c9d''');
  v_def := replace(v_def, '''MD5_LECTOR_PENDIENTE_000000000000''', '''27d25609c74e04c58f82e36af45d7327''');
  execute v_def;
end $reversa$;
comment on function private.assert_gestion_diaria_analista() is
  'Trinquete de Gestión Diaria F3 (el día del analista): puerta y núcleos INVOKER con ACL exacta, huellas selladas (puerta, núcleo, agregador, lector, umbrales, roster), cola v2 en su forma y perilla del abandono bajo RLS.';

-- 2. El lector: cuerpo de producción (20260924201358, vivo el 19/10/2026, md5 27d25609…).
create or replace function private.gestion_diaria_llamadas_eventos(
  p_ini timestamptz,p_fin timestamptz,p_vendedor_ids uuid[])
returns table(vendedor_id uuid,id uuid,lead_id uuid,tipo text,creado_en timestamptz,
  resultado text,util boolean,hora integer)
language sql stable security invoker set search_path='' as $$
  select a.creado_por,a.id,a.lead_id,a.tipo,a.creado_en,
    coalesce(a.metadata->>'resultado','sin_resultado'),
    coalesce(a.metadata->>'resultado','') not in ('numero_errado','no_es_la_persona'),
    extract(hour from a.creado_en at time zone 'America/Lima')::integer
  from crm.actividades a where
    (a.creado_por=any(p_vendedor_ids)
      or (a.creado_por is null and array_position(p_vendedor_ids,null) is not null))
    and a.tipo in ('llamada_realizada','llamada_no_contestada')
    and a.creado_en>=p_ini and a.creado_en<p_fin;
$$;
comment on function private.gestion_diaria_llamadas_eventos(timestamptz, timestamptz, uuid[]) is null;

-- 3. El agregador: cuerpo de producción (vivo el 19/10/2026, md5 7c5d14e6…).
CREATE OR REPLACE FUNCTION private.gestion_diaria_llamadas(p_ini timestamp with time zone, p_fin timestamp with time zone, p_vendedor_ids uuid[])
 RETURNS TABLE(vendedor_id uuid, llamadas integer, contestadas integer, utiles integer, leads_tocados integer, citas_agendadas integer, primera_llamada_en timestamp with time zone, ultima_llamada_en timestamp with time zone, por_resultado jsonb, por_hora jsonb)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with vendedores as (
    select distinct v.id from unnest(p_vendedor_ids) as v(id)
  ),
  ll as (
    select * from private.gestion_diaria_llamadas_eventos(p_ini,p_fin,p_vendedor_ids)
  ),
  agg as (
    select l.vendedor_id,
           cardinality(array_agg(l.id)) as llamadas,
           -- Contestadas ⊆ útiles POR CONSTRUCCIÓN: la tasa nunca puede pasar del
           -- 100 % aunque una fila histórica llevara un resultado incoherente
           -- con su tipo (hoy no hay ninguna: medido en producción el 20/09).
           coalesce(cardinality(array_agg(l.id) filter (where l.tipo = 'llamada_realizada' and l.util)), 0) as contestadas,
           coalesce(cardinality(array_agg(l.id) filter (where l.util)), 0) as utiles,
           cardinality(array_agg(distinct l.lead_id)) as leads_tocados,
           min(l.creado_en) as primera_llamada_en,
           max(l.creado_en) as ultima_llamada_en
    from ll l
    group by l.vendedor_id
  ),
  por_resultado as (
    select r.vendedor_id, jsonb_object_agg(r.resultado, r.n) as por_resultado
    from (
      select l.vendedor_id, l.resultado, cardinality(array_agg(l.id)) as n
      from ll l
      group by l.vendedor_id, l.resultado
    ) r
    group by r.vendedor_id
  ),
  por_hora as (
    select h.vendedor_id,
           jsonb_agg(jsonb_build_object('hora', h.hora, 'llamadas', h.n, 'contestadas', h.c) order by h.hora) as por_hora
    from (
      select l.vendedor_id, l.hora, cardinality(array_agg(l.id)) as n,
             coalesce(cardinality(array_agg(l.id) filter (where l.tipo = 'llamada_realizada')), 0) as c
      from ll l
      group by l.vendedor_id, l.hora
    ) h
    group by h.vendedor_id
  ),
  citas as (
    -- Cita agendada = tarea de cita CREADA en la ventana por el analista (la
    -- misma definición que metricas_agenda_fn). Las reprogramadas crean otra
    -- tarea y cuentan igual que allí.
    select t.vendedor_id, cardinality(array_agg(t.id)) as citas_agendadas
    from crm.tareas t
    where (t.vendedor_id in (select v.id from vendedores v)
      or (t.vendedor_id is null and array_position(p_vendedor_ids, null) is not null))
      and t.tipo = 'reunion'
      and t.creado_en >= p_ini
      and t.creado_en <  p_fin
    group by t.vendedor_id
  )
  select v.id,
         coalesce(a.llamadas, 0),
         coalesce(a.contestadas, 0),
         coalesce(a.utiles, 0),
         coalesce(a.leads_tocados, 0),
         coalesce(c.citas_agendadas, 0),
         a.primera_llamada_en,
         a.ultima_llamada_en,
         coalesce(r.por_resultado, '{}'::jsonb),
         coalesce(h.por_hora, '[]'::jsonb)
  from vendedores v
  left join agg a on a.vendedor_id is not distinct from v.id
  left join por_resultado r on r.vendedor_id is not distinct from v.id
  left join por_hora h on h.vendedor_id is not distinct from v.id
  left join citas c on c.vendedor_id is not distinct from v.id
  order by v.id;
$function$;
comment on function private.gestion_diaria_llamadas(timestamptz, timestamptz, uuid[]) is
  'NÚCLEO (Gestión Diaria): la definición única de llamada (realizada + no contestada), contacto (realizada), útil (resultado ∉ numero_errado/no_es_la_persona; sin resultado cuenta como útil), leads tocados, citas agendadas (tarea reunion creada en la ventana), primera/última llamada, desglose por resultado y por hora Lima, por analista y ventana [p_ini, p_fin). Bajo la RLS del actor; sin contadores crudos.';

-- 4. Ayudante y mutantes fuera.
drop function private.assert_gestion_diaria_llamadas_clientes_mutantes();
drop function private.gestion_diaria_llamadas_clientes_eventos(timestamptz, timestamptz, uuid[]);

do $postflight$
declare v_msg text;
begin
  if md5(pg_get_functiondef('private.gestion_diaria_llamadas_eventos(timestamptz,timestamptz,uuid[])'::regprocedure)) <> '27d25609c74e04c58f82e36af45d7327'
     or md5(pg_get_functiondef('private.gestion_diaria_llamadas(timestamptz,timestamptz,uuid[])'::regprocedure)) <> '7c5d14e65cc0e55e57214589d11e9c9d' then
    raise exception 'REVERSA llamadas_clientes: el lector o el agregador no volvieron al cuerpo de produccion (% / %)',
      md5(pg_get_functiondef('private.gestion_diaria_llamadas_eventos(timestamptz,timestamptz,uuid[])'::regprocedure)),
      md5(pg_get_functiondef('private.gestion_diaria_llamadas(timestamptz,timestamptz,uuid[])'::regprocedure));
  end if;
  if pg_get_functiondef('private.assert_gestion_diaria_analista()'::regprocedure) like '%llamadas_clientes%'
     or pg_get_functiondef('private.assert_gestion_diaria_analista()'::regprocedure) not like '%7c5d14e65cc0e55e57214589d11e9c9d%'
     or pg_get_functiondef('private.assert_gestion_diaria_analista()'::regprocedure) not like '%27d25609c74e04c58f82e36af45d7327%'
     or pg_get_functiondef('private.assert_gestion_diaria_citas()'::regprocedure) not like '%7c5d14e65cc0e55e57214589d11e9c9d%'
     or pg_get_functiondef('private.assert_gestion_diaria_pulso()'::regprocedure) not like '%7c5d14e65cc0e55e57214589d11e9c9d%'
     or pg_get_functiondef('private.assert_gestion_diaria_pulso()'::regprocedure) not like '%27d25609c74e04c58f82e36af45d7327%' then
    raise exception 'REVERSA llamadas_clientes: algun gate no volvio a sellar las huellas de produccion';
  end if;
  -- El gate de citas no depende del roster: debe quedar verde tras la reversa.
  v_msg := private.assert_gestion_diaria_citas();
  raise notice 'REVERSA llamadas_clientes: gate de citas %', v_msg;
end $postflight$;
commit;
