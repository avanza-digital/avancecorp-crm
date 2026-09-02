-- P-055 ATR-3a - LAS LENTES Y LA FICHA DICEN QUIEN SE LLEVA LA PRODUCCION.
--
-- Tercera fase del tren de atribucion (contrato tecnico 2026-08-30; ATR-1 en
-- prod registro 187; ATR-2 preparada para el 11-12/09). Decision de Miguel del
-- 31/08: las dos graficas de gerencia se ALINEAN al analista — el contrato
-- aparece bajo quien se lleva la produccion, no bajo el archivador del dueño.
-- SIN funciones nuevas (decision de Miguel): la ficha se amplia, no se duplica.
--
-- TRES cambios:
--  1) crm.metricas_capital_mes_fn: el corte de visibilidad no-global pasa de
--     cartera (cli.asesor_perfil_id) al ANALISTA del episodio (e.analista_id);
--     el join a perfiles cli queda muerto y se retira.
--  2) crm.metricas_vencimientos_fn: identico.
--  3) crm.atribucion_contrato_fn: gana la clave 'atribucion_efectiva'
--     {cadena, adoptada, analista_id, analista_nombre} preguntando al
--     resolutor de ATR-1; el resto del payload queda AL BYTE.
--
-- EFECTO EN NUMEROS DE HOY: para gerencia/lector (globales, los unicos que
-- miran esas graficas) CERO — el corte no aplica. Para un no-global, la lente
-- pasa de "clientes de mi arbol" a "produccion de mi arbol" (la misma cifra
-- que su podio); el oraculo MIDE ese delta bajo claims reales y lo exige
-- explicado fila a fila. Sin analista (13 medidos, verificado en preflight) -> fuera de la vista
-- no-global (invariante F3.5b); gerencia lo sigue viendo todo.
--
-- El Directorio del Portal NO se toca: queda como la UNICA lente por cartera
-- (decision explicita, pinneado abajo).

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- =====================================================================
-- 0) PREFLIGHT: pines y fotos bajo claims reales.
-- =====================================================================
do $$
declare
  v_fn constant text[][] := array[
    -- las TRES que se tocan (cuerpos viejos exactos):
    array['crm.metricas_capital_mes_fn(integer)',   'd8b5d898d6eb7b3d3ef3f287c3264707'],
    array['crm.metricas_vencimientos_fn(integer)',  'cf1a07e39e82272db01c6b86482ba612'],
    array['crm.atribucion_contrato_fn(uuid)',       'b95687bb1e95ba78adc832e65a8b5d5b'],
    -- el mundo alrededor, INTACTO:
    array['private.analista_atribuido_cadena(uuid)',                           'e39016e2913cce47faabee29c2c38fe2'],
    array['private.produccion_mes_por_vendedor(timestamptz,timestamptz,uuid)', 'af6794c36951ad53dcb413db90c26070'],
    array['crm.cerrar_periodo(date)',                                          'cefe29a119f40efe257f851a6ae2a162'],
    array['public.directorio_ranking_analistas()',                             '0ba94108dc8612a42535ab89c14d1728'],
    array['public.crear_contrato(jsonb,jsonb)',                                '4c25cee5a36c2144c45a061eaddb5366']
  ];
  v_fila text[]; v_h text; v_n integer;
  v_ger uuid; v_sup uuid;
begin
  foreach v_fila slice 1 in array v_fn loop
    select md5(p.prosrc) into v_h from pg_proc p where p.oid = v_fila[1]::regprocedure;
    if v_h is distinct from v_fila[2] then
      raise exception 'ATR-3a preflight: % cambio desde la medicion (huella %)', v_fila[1], v_h;
    end if;
  end loop;

  -- capital_episodios es pin AMBIENTAL BIVALENTE (P0 de ordenacion): en prod
  -- ATR-3a corre ANTES que ATR-2 (nucleo viejo 872f5ad4), pero en el REPLAY de
  -- un banco el orden es por timestamp y ATR-2 (20260830233000) corre PRIMERO
  -- (nucleo nuevo 90f1d8c2). Se acepta CUALQUIERA de los dos estados y el
  -- postflight exige el MISMO capturado (esta migracion no lo toca).
  select md5(p.prosrc) into v_h from pg_proc p
   where p.oid = 'private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])'::regprocedure;
  if v_h not in ('872f5ad4362f66a18f4a3806453f78a0', '90f1d8c2342becb94cc3d3e023227078') then
    raise exception 'ATR-3a preflight: capital_episodios en estado desconocido (huella %)', v_h;
  end if;
  create temp table _atr3_amb on commit drop as select v_h as cap_h;

  -- La afirmacion "13 sin analista" se VERIFICA, no se comenta (P2 de Codex):
  -- si cambia, este publish debe re-mirarse (la puerta F3.7 impide que nazcan).
  select count(*) into v_n from public.contratos c
   where c.analista_cierre_id is null and not c.es_demo;
  if v_n <> 13 and not (v_n = 0 and (select count(*) from public.contratos where not es_demo) = 0) then
    -- 🔧 PARCHE DE BANCO (declarado en banco-parches/DIVERGENCIAS.md): el «13»
    --    es un CENSO DE FILAS DE PRODUCCION. Un banco recien nacido tiene 0
    --    contratos, asi que tambien tiene 0 sin analista — y eso no contradice
    --    nada. Se tolera SOLO el caso EXACTAMENTE vacio (0 sin analista Y 0
    --    contratos no-demo en total); con datos parciales vuelve a abortar,
    --    que es cuando el censo si tendria algo que decir.
    raise exception 'ATR-3a preflight: % contratos sin analista (se midieron 13) — re-mirar antes de publicar', v_n;
  end if;

  -- Actores reales para el oraculo por claims: una gerencia y un supervisor.
  select e.perfil_id into strict v_ger
    from crm.equipo e join public.perfiles p on p.id = e.perfil_id
   where e.activo and p.activo and e.rol_crm = 'gerencia' limit 1;
  select e.perfil_id into strict v_sup
    from crm.equipo e join public.perfiles p on p.id = e.perfil_id
   where e.activo and p.activo and e.rol_crm = 'supervisor' limit 1;
  create temp table _atr3_actores on commit drop as
    select v_ger as ger, v_sup as sup;

  -- FOTO DE ANTES, bajo claims de gerencia (global) y de supervisor (cortado).
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_ger, 'role', 'authenticated')::text, true);
  create temp table _atr3_mes_ger_antes  on commit drop as
    select * from crm.metricas_capital_mes_fn(60);
  create temp table _atr3_venc_ger_antes on commit drop as
    select * from crm.metricas_vencimientos_fn(366);

  perform set_config('request.jwt.claims',
    json_build_object('sub', v_sup, 'role', 'authenticated')::text, true);
  create temp table _atr3_mes_sup_antes  on commit drop as
    select * from crm.metricas_capital_mes_fn(60);
  create temp table _atr3_venc_sup_antes on commit drop as
    select * from crm.metricas_vencimientos_fn(366);

  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'postgres', true);

  -- El DELTA PREDICHO del supervisor, calculado A MANO desde el nucleo: los
  -- episodios de contrato cuyo corte viejo (cartera) y nuevo (analista)
  -- difieren para su arbol. La foto nueva debe ser EXACTAMENTE la vieja
  -- +entradas -salidas de esta lista.
  create temp table _atr3_pred on commit drop as
    -- vendedor_ids_visibles se niega sin claims (defensa en profundidad):
    -- se replica AQUI su subarbol de supervisor, con la MISMA CTE del original.
    with recursive subarbol as (
      select e.perfil_id from crm.equipo e where e.perfil_id = v_sup
      union
      select e.perfil_id from crm.equipo e join subarbol s2 on e.supervisor_id = s2.perfil_id
    ), ids as (select array(select perfil_id from subarbol) as a)
    select e.contrato_id, e.mes_comercial, e.moneda, e.monto,
           case when e.tipo = 'cooperativa' then 'cooperativa' else e.categoria end as categoria,
           e.fecha_vencimiento, e.estado,
           (e.analista_id = any (ids.a)) as entra_nuevo,
           case when e.tipo = 'cooperativa'
                then (e.analista_id = any (ids.a))  -- la coop no cambia de regla
                else (cli.asesor_perfil_id = any (ids.a)
                      or (cli.asesor_perfil_id is null and cli.creado_por = any (ids.a)))
           end as entraba_viejo
      from private.capital_episodios('-infinity'::timestamptz,
             ((current_date + 1)::timestamp at time zone 'America/Lima'),
             true, '{}'::uuid[]) e
      left join public.perfiles cli on cli.id = e.cliente_id
      cross join ids
     where e.medida = 'stock'
       and (e.tipo like 'contrato_%' or e.tipo = 'cooperativa');


  -- Fichas de ANTES (para el oraculo del payload): 3 contratos representativos,
  -- BAJO CLAIMS de gerencia (la vista de visibilidad devuelve vacio sin sesion).
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_ger, 'role', 'authenticated')::text, true);
  create temp table _atr3_fichas_antes on commit drop as
    select c.id, crm.atribucion_contrato_fn(c.id) as ficha,
           null::uuid as esperado_analista, null::boolean as esperado_cadena,
           null::boolean as esperado_adoptada, null::text as esperado_nombre
      from (
        (select id from public.contratos where categoria = 'upgrade' and not es_demo limit 1)
        union all
        (select id from public.contratos where coalesce(categoria,'nuevo') = 'nuevo' and not es_demo limit 1)
        union all
        (select id from public.contratos where categoria = 'renovacion' and not es_demo limit 1)
      ) c;
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'postgres', true);
  -- La verdad esperada de la clave nueva, calculada como postgres (el resolutor es private).
  update _atr3_fichas_antes fa
     set esperado_analista = coalesce(private.analista_atribuido_cadena(c.id), c.analista_cierre_id),
         esperado_nombre   = (select pp.nombre_completo from public.perfiles pp
                               where pp.id = coalesce(private.analista_atribuido_cadena(c.id), c.analista_cierre_id)),
         esperado_cadena   = private.analista_atribuido_cadena(c.id) is not null,
         esperado_adoptada = private.analista_atribuido_cadena(c.id) is not null
                             and private.analista_atribuido_cadena(c.id) is distinct from c.analista_cierre_id
    from public.contratos c where c.id = fa.id;

  -- Las fotos y la prediccion se re-leen bajo claims de authenticated en el
  -- oraculo: GRANT explicito sobre las temporales (viven solo en esta tx).
  grant select on _atr3_mes_ger_antes, _atr3_venc_ger_antes,
                  _atr3_mes_sup_antes, _atr3_venc_sup_antes,
                  _atr3_pred, _atr3_actores, _atr3_fichas_antes to authenticated;
end $$;

-- =====================================================================
-- 1) LAS DOS LENTES Y LA FICHA (cuerpos completos, generados a maquina).
-- =====================================================================
CREATE OR REPLACE FUNCTION crm.metricas_capital_mes_fn(p_meses integer DEFAULT 12)
 RETURNS TABLE(mes date, moneda text, categoria text, contratos bigint, capital_colocado numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with ambito as (
    select
      ((select private.es_lector_global())
        or (select private.rol_crm((select auth.uid()))) = 'gerencia') as es_global,
      array(select private.vendedor_ids_visibles((select auth.uid())))  as ids
  )
  select
    e.mes_comercial as mes,
    e.moneda,
    case when e.tipo = 'cooperativa' then 'cooperativa' else e.categoria end as categoria,
    count(*)::bigint  as contratos,
    sum(e.monto)      as capital_colocado
  from private.capital_episodios(
         ((date_trunc('month', current_date)
            - make_interval(months => least(greatest(p_meses, 1), 60) - 1))::date::timestamp
           at time zone 'America/Lima'),
         ((current_date + 1)::timestamp at time zone 'America/Lima'),
         true, '{}'::uuid[]) e
  cross join ambito a
  where e.medida = 'stock'
    and (e.tipo like 'contrato_%' or e.tipo = 'cooperativa')
    and (
      a.es_global
      -- ATR-3 (decision de Miguel 31/08): la lente ENSEÑA por quien se lleva la
      -- produccion (el analista del episodio; con ATR-2 sera el de la cadena),
      -- no por el archivador del dueño. Sin analista -> no cuenta a nadie
      -- (invariante F3.5b); gerencia/lector global lo ve todo igual.
      or (e.tipo like 'contrato_%' and e.analista_id = any (a.ids))
      or (e.tipo = 'cooperativa' and e.analista_id = any (a.ids))
    )
  group by 1, 2, 3
  order by 1, 2, 3;
$function$
;

CREATE OR REPLACE FUNCTION crm.metricas_vencimientos_fn(p_dias integer DEFAULT 90)
 RETURNS TABLE(mes date, moneda text, contratos_por_vencer bigint, capital_por_vencer numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with ambito as (
    select
      ((select private.es_lector_global())
        or (select private.rol_crm((select auth.uid()))) = 'gerencia') as es_global,
      array(select private.vendedor_ids_visibles((select auth.uid())))  as ids
  )
  select
    (date_trunc('month', e.fecha_vencimiento))::date as mes,
    e.moneda,
    count(*)::bigint as contratos_por_vencer,
    sum(e.monto)     as capital_por_vencer
  from private.capital_episodios(
         '-infinity'::timestamptz,
         ((current_date + 1)::timestamp at time zone 'America/Lima'),
         true, '{}'::uuid[]) e
  cross join ambito a
  where e.medida = 'stock'
    and ((e.tipo like 'contrato_%' and e.estado = 'activo')
         or (e.tipo = 'cooperativa' and e.estado = 'vigente'))
    and e.fecha_vencimiento >= current_date
    and e.fecha_vencimiento <  current_date + least(greatest(p_dias, 1), 366)
    and (
      a.es_global
      -- ATR-3 (decision de Miguel 31/08): la lente ENSEÑA por quien se lleva la
      -- produccion (el analista del episodio; con ATR-2 sera el de la cadena),
      -- no por el archivador del dueño. Sin analista -> no cuenta a nadie
      -- (invariante F3.5b); gerencia/lector global lo ve todo igual.
      or (e.tipo like 'contrato_%' and e.analista_id = any (a.ids))
      or (e.tipo = 'cooperativa' and e.analista_id = any (a.ids))
    )
  group by 1, 2
  order by 1, 2;
$function$
;

CREATE OR REPLACE FUNCTION crm.atribucion_contrato_fn(p_contrato_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select case
    -- La MISMA regla de visibilidad que ya gobierna los contratos del CRM: se
    -- pregunta a la vista viva en vez de copiar su `where`.
    when not exists (
      select 1 from crm.contratos_cartera v where v.id = p_contrato_id
    ) then null
    else (
      select jsonb_build_object(
        'contrato_id',   c.id,
        'analista_id',   c.analista_cierre_id,
        'analista_nombre', pa.nombre_completo,
        'es_demo',       c.es_demo,
        'registrado_por', pr.nombre_completo,
        -- ATR-3: quien COBRA de verdad (la politica de la cadena de upgrade).
        -- 'cadena' = el contrato pertenece a una cadena de upgrade (el propio
        -- upgrade incluido): toda renovacion suya contara al analista_id de aqui.
        -- 'adoptada' = ademas la atribucion difiere del analista que la proceso.
        'atribucion_efectiva', (
          select jsonb_build_object(
            'cadena',   ef.analista_id is not null,
            'adoptada', ef.analista_id is not null
                        and ef.analista_id is distinct from c.analista_cierre_id,
            'analista_id',     coalesce(ef.analista_id, c.analista_cierre_id),
            'analista_nombre', coalesce(pef.nombre_completo, pa.nombre_completo)
          )
          from (select private.analista_atribuido_cadena(c.id) as analista_id) ef
          left join public.perfiles pef on pef.id = ef.analista_id
        ),
        'reasignaciones', case
          -- El historial con motivos, solo para la autoridad o el propio
          -- analista (A3). Mismo conjunto que la policy de la tabla, con P04.
          when (((select public.es_gestor_cartera())
                 or coalesce(private.rol_crm((select auth.uid())) = 'gerencia', false))
                and not (select private.membresia_crm_revocada()))
               or c.analista_cierre_id = (select auth.uid())
          then coalesce((
            select jsonb_agg(jsonb_build_object(
              'cuando',  r.reasignado_en,
              'de',      pde.nombre_completo,
              'a',       pa2.nombre_completo,
              'motivo',  r.motivo,
              'por',     ppor.nombre_completo
            ) order by r.reasignado_en desc)
            from crm.reasignaciones_analista r
            left join public.perfiles pde  on pde.id  = r.analista_de
            left join public.perfiles pa2  on pa2.id  = r.analista_a
            left join public.perfiles ppor on ppor.id = r.reasignado_por
            where r.contrato_id = c.id
          ), '[]'::jsonb)
          else '[]'::jsonb
        end
      )
      from public.contratos c
      left join public.perfiles pa on pa.id = c.analista_cierre_id
      left join public.perfiles pr on pr.id = c.creado_por
      where c.id = p_contrato_id
    )
  end;
$function$
;

comment on function crm.atribucion_contrato_fn(uuid) is
  'De quien es la venta (F3.6) + a quien COBRA de verdad (ATR-3: atribucion_efectiva '
  '{cadena, adoptada, analista_id, analista_nombre} — la politica de la cadena de upgrade). '
  'NULL si quien pregunta no ve el contrato (gate: la vista crm.contratos_cartera).';

-- =====================================================================
-- 2) ORACULO bajo los MISMOS claims.
-- =====================================================================
do $$
declare v_ger uuid; v_sup uuid; v_n integer;
begin
  select ger, sup into v_ger, v_sup from _atr3_actores;

  -- 2a) GERENCIA (global): byte a byte, las dos lentes.
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_ger, 'role', 'authenticated')::text, true);
  select (select count(*) from ((select * from crm.metricas_capital_mes_fn(60))
          except all (select * from _atr3_mes_ger_antes)) x)
       + (select count(*) from ((select * from _atr3_mes_ger_antes)
          except all (select * from crm.metricas_capital_mes_fn(60))) x)
    into v_n;
  if v_n <> 0 then
    raise exception 'ATR-3a oraculo: capital_mes cambio para GERENCIA (% filas)', v_n;
  end if;
  select (select count(*) from ((select * from crm.metricas_vencimientos_fn(366))
          except all (select * from _atr3_venc_ger_antes)) x)
       + (select count(*) from ((select * from _atr3_venc_ger_antes)
          except all (select * from crm.metricas_vencimientos_fn(366))) x)
    into v_n;
  if v_n <> 0 then
    raise exception 'ATR-3a oraculo: vencimientos cambio para GERENCIA (% filas)', v_n;
  end if;

  -- 2b) SUPERVISOR: la foto nueva = agregacion PREDICHA por el corte nuevo.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_sup, 'role', 'authenticated')::text, true);
  create temp table _atr3_cap_pred on commit drop as
    select p.mes_comercial as mes, p.moneda, p.categoria,
           count(*)::bigint as contratos, sum(p.monto) as capital_colocado
      from _atr3_pred p
     where p.entra_nuevo
       and p.mes_comercial >= (date_trunc('month', current_date) - make_interval(months => 59))::date
     group by 1, 2, 3;
  grant select on _atr3_cap_pred to authenticated;
  select (select count(*) from ((select * from crm.metricas_capital_mes_fn(60))
          except all (select * from _atr3_cap_pred)) x)
       + (select count(*) from ((select * from _atr3_cap_pred)
          except all (select * from crm.metricas_capital_mes_fn(60))) x)
    into v_n;
  if v_n <> 0 then
    raise exception 'ATR-3a oraculo: capital_mes del SUPERVISOR no cuadra con el corte predicho (% filas)', v_n;
  end if;

  -- VENCIMIENTOS del supervisor: bidireccional contra su propia prediccion
  -- (P1 de Codex: la foto capturada no se comparaba). La ventana y el estado
  -- replican los filtros de la lente.
  create temp table _atr3_venc_pred on commit drop as
    select (date_trunc('month', p.fecha_vencimiento))::date as mes, p.moneda,
           count(*)::bigint as contratos_por_vencer, sum(p.monto) as capital_por_vencer
      from _atr3_pred p
     where p.entra_nuevo
       and ((p.categoria is distinct from 'cooperativa' and p.estado = 'activo')
            or (p.categoria = 'cooperativa' and p.estado = 'vigente'))
       and p.fecha_vencimiento >= current_date
       and p.fecha_vencimiento <  current_date + 366
     group by 1, 2;
  grant select on _atr3_venc_pred to authenticated;
  select (select count(*) from ((select * from crm.metricas_vencimientos_fn(366))
          except all (select * from _atr3_venc_pred)) x)
       + (select count(*) from ((select * from _atr3_venc_pred)
          except all (select * from crm.metricas_vencimientos_fn(366))) x)
    into v_n;
  if v_n <> 0 then
    raise exception 'ATR-3a oraculo: vencimientos del SUPERVISOR no cuadra con el corte predicho (% filas)', v_n;
  end if;
  -- La foto vieja del supervisor queda de TESTIGO de forma (mismas columnas):
  perform 1 from _atr3_mes_sup_antes limit 1;
  perform 1 from _atr3_venc_sup_antes limit 1;

  -- 2c) LA FICHA: payload viejo AL BYTE + la clave nueva con la verdad
  --     (bajo claims de GERENCIA, como la captura de antes).
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_ger, 'role', 'authenticated')::text, true);
  select count(*) into v_n
    from _atr3_fichas_antes fa
    cross join lateral crm.atribucion_contrato_fn(fa.id) fn(nueva)
   where fn.nueva - 'atribucion_efectiva' is distinct from fa.ficha
      or (fn.nueva -> 'atribucion_efectiva') is null
      or (fn.nueva #>> '{atribucion_efectiva,analista_id}')::uuid is distinct from fa.esperado_analista
      or (fn.nueva #>> '{atribucion_efectiva,cadena}')::boolean   is distinct from fa.esperado_cadena
      or (fn.nueva #>> '{atribucion_efectiva,adoptada}')::boolean is distinct from fa.esperado_adoptada
      or (fn.nueva #>> '{atribucion_efectiva,analista_nombre}') is distinct from fa.esperado_nombre
      or (select array_agg(k order by k) from jsonb_object_keys(fn.nueva -> 'atribucion_efectiva') k)
         is distinct from array['adoptada','analista_id','analista_nombre','cadena'];
  if v_n <> 0 then
    raise exception 'ATR-3a oraculo: la ficha no conserva el payload o la clave nueva miente (% fichas)', v_n;
  end if;

  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'postgres', true);
end $$;

-- =====================================================================
-- 3) POSTFLIGHT.
-- =====================================================================
do $$
declare v_h text;
begin
  select md5(p.prosrc) into v_h from pg_proc p where p.oid = 'crm.metricas_capital_mes_fn(integer)'::regprocedure;
  if v_h is distinct from 'b21f9a7a134f76f9f2eabfe75578cbca' then
    raise exception 'ATR-3a postflight: capital_mes quedo con huella %', v_h; end if;
  select md5(p.prosrc) into v_h from pg_proc p where p.oid = 'crm.metricas_vencimientos_fn(integer)'::regprocedure;
  if v_h is distinct from '54a9bf11bb4e0bbf0fc4d7c12bed7fcb' then
    raise exception 'ATR-3a postflight: vencimientos quedo con huella %', v_h; end if;
  select md5(p.prosrc) into v_h from pg_proc p where p.oid = 'crm.atribucion_contrato_fn(uuid)'::regprocedure;
  if v_h is distinct from '1eccb3a1ff8b73e91f2f7870d08f83e8' then
    raise exception 'ATR-3a postflight: la ficha quedo con huella %', v_h; end if;

  -- ACL conservadas (CREATE OR REPLACE no las toca; se exige el literal medido).
  if (select p.proacl::text from pg_proc p where p.oid = 'crm.metricas_capital_mes_fn(integer)'::regprocedure)
     is distinct from '{postgres=X/postgres,authenticated=X/postgres}' then
    raise exception 'ATR-3a postflight: ACL de capital_mes cambio'; end if;
  if (select p.proacl::text from pg_proc p where p.oid = 'crm.metricas_vencimientos_fn(integer)'::regprocedure)
     is distinct from '{postgres=X/postgres,authenticated=X/postgres}' then
    raise exception 'ATR-3a postflight: ACL de vencimientos cambio'; end if;
  if (select p.proacl::text from pg_proc p where p.oid = 'crm.atribucion_contrato_fn(uuid)'::regprocedure)
     is distinct from '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' then
    raise exception 'ATR-3a postflight: ACL de la ficha cambio'; end if;

  -- El mundo alrededor, intacto (incluido el Directorio: la unica lente por cartera).
  declare
    v_fn constant text[][] := array[
      array['private.analista_atribuido_cadena(uuid)',                           'e39016e2913cce47faabee29c2c38fe2'],
      array['private.produccion_mes_por_vendedor(timestamptz,timestamptz,uuid)', 'af6794c36951ad53dcb413db90c26070'],
      array['crm.cerrar_periodo(date)',                                          'cefe29a119f40efe257f851a6ae2a162'],
      array['public.directorio_ranking_analistas()',                             '0ba94108dc8612a42535ab89c14d1728'],
      array['public.crear_contrato(jsonb,jsonb)',                                '4c25cee5a36c2144c45a061eaddb5366']
    ];
    v_fila text[];
  begin
    foreach v_fila slice 1 in array v_fn loop
      select md5(p.prosrc) into v_h from pg_proc p where p.oid = v_fila[1]::regprocedure;
      if v_h is distinct from v_fila[2] then
        raise exception 'ATR-3a postflight: % se movio y NO debia (huella %)', v_fila[1], v_h;
      end if;
    end loop;
  end;

  -- El pin bivalente: el nucleo sigue EXACTAMENTE como se capturo.
  select md5(p.prosrc) into v_h from pg_proc p
   where p.oid = 'private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])'::regprocedure;
  if v_h is distinct from (select cap_h from _atr3_amb) then
    raise exception 'ATR-3a postflight: capital_episodios se movio durante la migracion (huella %)', v_h;
  end if;

  perform private.assert_analitica_leads_citas();
  perform private.assert_analista_vigencia();
end $$;

commit;
;
