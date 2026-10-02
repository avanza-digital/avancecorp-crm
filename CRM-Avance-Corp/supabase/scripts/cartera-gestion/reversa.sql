-- REVERSA de 20261001154153_crm_cartera_filtro_gestion: retira la firma de 13 argumentos de
-- crm.cartera_filtrada_fn y reinstala la de 12 publicada por 20260929195918 (definición tomada
-- del banco a paridad con producción, md5 7169d94239dcb191bafa3faed46f916f), con su declaración
-- analítica original, y resella. No toca datos.
-- ANTES: retirar el frente que envía p_gestion (las pestañas abiertas conservan su JavaScript
-- hasta recargar: con la firma de 12 recibirían PGRST202 al pedir «Gestionado»).
-- Guardas: no retira una función corregida después de esta entrega ni resella una lista de
-- exenciones alterada por fuera. Conserva la fila de schema_migrations: anotarlo en MIGRACIONES.md.
-- LÍMITE: NO detecta un consumidor de SERVIDOR que ya pase p_gestion. plpgsql enlaza tarde: una
-- función que llame crm.cartera_filtrada_fn(..., p_gestion => ...) seguiría existiendo y fallaría
-- al EJECUTARSE contra la firma de 12. Hoy no hay ninguno (resumen_cartera_fn solo pasa
-- p_limite); antes de revertir, buscarlo:
--   select p.oid::regprocedure from pg_proc p where p.prosrc ~ 'p_gestion' and p.proname <> 'cartera_filtrada_fn';
-- GENERADO por supabase/scripts/cartera-gestion/generar-reversa.mjs; no editar a mano.
begin;
set local lock_timeout = '10s';
set local statement_timeout = '30s';
set local search_path = '';

lock table private.analitica_leads_citas_exenciones,
  private.analitica_lc_sello in share row exclusive mode;

do $preflight$
declare
  f12 constant text := 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean)';
  f13 constant text := 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)';
  f13_larga constant text := 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)';
begin
  if (
    to_regprocedure(f13) is not null
    and to_regprocedure(f12) is null
    and (select count(*) from pg_proc where proname = 'cartera_filtrada_fn'
           and pronamespace = 'crm'::regnamespace) = 1
  ) is not true then
    raise exception 'REVERSA: la firma de 13 argumentos no es la unica instalada';
  end if;
  -- Exactamente lo que publicó 20261001154153: una corrección posterior no se pisa.
  if (
    md5(pg_get_functiondef(to_regprocedure(f13))) = 'bf06666fb8ef533a39a50c7d70420153'
    and (select e.huella from private.analitica_leads_citas_exenciones e where e.objeto = f13_larga) = '22284ce4b9e70790d6e23622f4cd6682'
    and exists (select 1 from private.contadores_crudos_leads_citas() c
                 where c.objeto = f13_larga and c.declarada and c.huella_ok)
  ) is not true then
    raise exception 'REVERSA: la funcion de 13 argumentos no es la publicada por 20261001154153';
  end if;
  if ((select s.sello from private.analitica_lc_sello s where s.id)
        = private.huella_exenciones_analitica_lc()) is not true then
    raise exception 'REVERSA: la lista de exenciones no coincide con su sello; no se resella a ciegas';
  end if;
end;
$preflight$;

create temporary table cartera_gestion_reversa on commit drop as
select
  (select to_jsonb(p) from (select proowner::regrole::text as duenio,
      prosecdef, provolatile, proconfig, proacl
    from pg_proc where oid = 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)'::regprocedure) p) as contrato,
  (select count(*) from private.contadores_crudos_leads_citas()) as censo,
  (select coalesce(string_agg(c.objeto, ',' order by c.objeto), '')
    from private.contadores_crudos_leads_citas() c
    where not (c.declarada and c.huella_ok)) as censo_rojo,
  (select jsonb_agg(to_jsonb(e) order by e.objeto)
    from private.analitica_leads_citas_exenciones e
    where e.objeto <> 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)') as otras,
  (select to_jsonb(e) - 'objeto' - 'huella' - 'razon'
    from private.analitica_leads_citas_exenciones e
    where e.objeto = 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)') as declaracion,
  md5(pg_get_functiondef('crm.resumen_cartera_fn()'::regprocedure)) as resumen_md5;

drop function crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text);

CREATE OR REPLACE FUNCTION crm.cartera_filtrada_fn(p_limite integer DEFAULT 50, p_antes_de timestamp with time zone DEFAULT NULL::timestamp with time zone, p_antes_id uuid DEFAULT NULL::uuid, p_etapa text DEFAULT NULL::text, p_vendedor_id uuid DEFAULT NULL::uuid, p_sin_asignar boolean DEFAULT false, p_texto text DEFAULT NULL::text, p_desde date DEFAULT NULL::date, p_hasta date DEFAULT NULL::date, p_origen text DEFAULT NULL::text, p_procedencia text DEFAULT NULL::text, p_reasignados boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_global boolean;
  v_visibles uuid[];
  v_texto text := nullif(btrim(p_texto), '');
  v_reparto boolean;
  v_digitos text;
  v_salida jsonb;
begin
  if v_uid is null or not private.puede_acceder_crm() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if p_limite is null or p_limite < 1 or p_limite > 200
     or (p_antes_de is null) <> (p_antes_id is null)
     or (p_sin_asignar and p_vendedor_id is not null)
     or (p_sin_asignar and p_desde is not null)
     or (p_desde is null) <> (p_hasta is null)
     or p_desde > p_hasta
     or p_hasta > (now() at time zone 'America/Lima')::date
     or (p_etapa is not null and p_etapa not in
       ('nuevo','contactado','reunion_agendada','propuesta_enviada','convertido','descartado'))
     -- Mismo dominio que el CHECK de crm.leads.origen: los 5 vigentes y los 3
     -- históricos (web, campania, whatsapp) siguen siendo consultables.
     or (p_origen is not null and p_origen not in
       ('referido','landing','formulario','oficina','otro','web','campania','whatsapp'))
     -- Procedencia: 'sistema' (puente automático) o 'manual' (una persona).
     -- Otro valor se rechaza: nunca un «cero resultados» silencioso.
     or (p_procedencia is not null and p_procedencia not in ('sistema','manual'))
     or (v_texto is not null and length(v_texto) < 2) then
    raise exception 'Filtros de cartera inválidos' using errcode = '22023';
  end if;
  v_texto := left(v_texto, 80);
  v_digitos := left(regexp_replace(v_texto, '\D', '', 'g'), 15);
  v_global := private.rol_crm(v_uid) = 'gerencia' or private.es_lector_global();
  v_visibles := array(select private.vendedor_ids_visibles(v_uid));
  v_reparto := private.cartera_puede_operar_reparto_fn();

  with recepciones as materialized (
    select * from private.cartera_recepciones_fn(p_desde,p_hasta)
  ), base as materialized (
    select l.id, l.nombre_completo, l.telefono, l.telefono_alternativo,
      l.telefono_alternativo_crudo, l.correo, l.dni, l.genero,
      l.fecha_nacimiento, l.distrito, l.origen, l.etapa, l.motivo_descarte,
      l.monto_estimado, l.moneda, l.categoria_interes, l.vendedor_id,
      l.asignado_supervisor_id, l.creado_en, l.tenencia_desde, l.convertido_en,
      l.contrato_id, l.actualizado_en, l.activo, l.nota, l.no_contactar,
      -- Procedencia sellada por el servidor: `alta_manual` (columna del 01/09)
      -- o, para los leads anteriores a ella, tener autor. El puente inserta
      -- como service_role sin autor: nunca cae en 'manual'.
      case when l.alta_manual or l.creado_por is not null then 'manual' else 'sistema' end as procedencia,
      l.creado_por as cargado_por,
      coalesce(mov.reasignado, false) as reasignado,
      r.recibido_en, coalesce(r.aproximado,false) as recepcion_aproximada
    from crm.leads l
    -- Una primera entrega desde la cola tiene vendedor_anterior NULL. Solo
    -- cuenta un analista ANTERIOR, incluso si volvió al mismo titular tras
    -- pasar por la bandeja. El evento lo emite el trigger del servidor.
    left join lateral (
      select true as reasignado
      from crm.actividades a
      where l.vendedor_id is not null
        and a.lead_id = l.id
        and a.tipo = 'reasignacion'
        and a.metadata ->> 'vendedor_anterior' is not null
      limit 1
    ) mov on true
    left join recepciones r on r.lead_id = l.id
    where l.activo is true
      and (v_global or l.vendedor_id = any(v_visibles)
        or (l.vendedor_id is null and (l.asignado_supervisor_id = any(v_visibles)
          or v_reparto)))
      and (p_desde is null or r.lead_id is not null)
      -- La consulta por recepción puede recuperar convertidos antiguos que
      -- siguen siendo visibles por RLS; sin fechas se conserva la ventana operativa.
      and (p_desde is not null or l.etapa <> 'convertido' or l.convertido_en >= now() - interval '45 days')
      and (p_etapa is null or l.etapa = p_etapa)
      -- El origen acota la MISMA base: filas, totales, capital y embudo juntos.
      and (p_origen is null or l.origen = p_origen)
      -- La procedencia acota esa misma base, con la misma regla que la columna
      -- `procedencia` de arriba.
      and (p_procedencia is null or (l.alta_manual or l.creado_por is not null) = (p_procedencia = 'manual'))
      and (not coalesce(p_reasignados,false) or coalesce(mov.reasignado,false))
      and (p_vendedor_id is null or l.vendedor_id = p_vendedor_id)
      and (not coalesce(p_sin_asignar,false) or l.vendedor_id is null)
      and (v_texto is null or strpos(lower(l.nombre_completo),lower(v_texto)) > 0
        or (length(v_digitos) >= 3 and (strpos(l.telefono,v_digitos) > 0
          or strpos(l.telefono_alternativo,v_digitos) > 0 or strpos(l.dni,v_digitos) > 0)))
  ), pagina as (
    select b.* from base b
    where p_antes_de is null or b.actualizado_en < p_antes_de
      or (b.actualizado_en = p_antes_de and b.id > p_antes_id)
    order by b.actualizado_en desc,b.id asc limit p_limite
  ), filas as (
    select p.*, uc.creado_en as ultimo_contacto_en
    from pagina p left join lateral (
      select act.creado_en from crm.actividades act
      where act.lead_id = p.id and act.tipo in ('llamada_realizada',
        'llamada_no_contestada','whatsapp_enviado','whatsapp_recibido','reunion_realizada')
      order by act.creado_en desc limit 1
    ) uc on true
  ), metricas as (
    select count(*) as vivos,
      count(*) filter(where etapa not in ('convertido','descartado')) as abiertos,
      count(*) filter(where etapa not in ('convertido','descartado') and vendedor_id is not null) as asignados,
      count(*) filter(where etapa not in ('convertido','descartado') and vendedor_id is null) as parkeados,
      count(*) filter(where etapa = 'convertido') as convertidos,
      count(*) filter(where etapa = 'descartado') as descartados,
      count(*) filter(where reasignado) as reasignados,
      count(*) filter(where etapa not in ('convertido','descartado') and vendedor_id is not null and moneda='PEN') as asignados_pen,
      count(*) filter(where etapa not in ('convertido','descartado') and vendedor_id is not null and moneda='USD') as asignados_usd
    from base
  ), capital as (
    select jsonb_object_agg(tipo,valor) as valor from (
      select t.tipo, jsonb_build_object(
        'pen',coalesce(sum(b.monto_estimado) filter(where b.moneda='PEN'),0),
        'usd',coalesce(sum(b.monto_estimado) filter(where b.moneda='USD'),0)) as valor
      from (values('asignado'),('parkeado'),('ganado')) t(tipo)
      left join base b on (t.tipo='ganado' and b.etapa='convertido')
        or (b.etapa not in ('convertido','descartado') and
          ((t.tipo='asignado' and b.vendedor_id is not null) or (t.tipo='parkeado' and b.vendedor_id is null)))
      group by t.tipo
    ) montos
  )
  select jsonb_build_object('version',1,'generado_en',now(),
    'desde',p_desde,'hasta',p_hasta,'origen',p_origen,'procedencia',p_procedencia,
    'reasignados',coalesce(p_reasignados,false),
    'items',coalesce((select jsonb_agg(to_jsonb(f) order by f.actualizado_en desc,f.id) from filas f),'[]'::jsonb),
    'resumen',jsonb_build_object('totales',(select to_jsonb(m) from metricas m),
      'capital',(select valor from capital),
      'conversion',jsonb_build_object(
        'convertidos',(select count(*) from base where etapa='convertido' and vendedor_id is not null),
        'base',(select count(*) from base where vendedor_id is not null),
        'pct',coalesce((select round(100.0 * count(*) filter(where etapa='convertido')
          / nullif(count(*),0))::int from base where vendedor_id is not null),0)),
      'descartes',jsonb_build_object(
        'total',(select count(*) from base where etapa='descartado'),
        'sin_motivo',(select count(*) from base where etapa='descartado' and motivo_descarte is null),
        'por_motivo',(select coalesce(jsonb_agg(to_jsonb(d) order by d.n desc,d.motivo),'[]'::jsonb)
          from (select motivo_descarte as motivo,count(*) as n from base
            where etapa='descartado' and motivo_descarte is not null group by motivo_descarte) d)),
      'sin_tocar',(select count(*) from base b where b.etapa not in('convertido','descartado')
        and b.vendedor_id is not null and not exists(select 1 from crm.actividades a
          where a.lead_id=b.id and a.tipo in ('llamada_realizada','llamada_no_contestada',
            'whatsapp_enviado','whatsapp_recibido','reunion_realizada'))),
      'embudo',(select jsonb_agg(jsonb_build_object('etapa',e.etapa,'n',
        (select count(*) from base b where b.etapa=e.etapa)) order by e.ord)
        from (values('nuevo',1),('contactado',2),('reunion_agendada',3),
          ('propuesta_enviada',4),('convertido',5),('descartado',6)) e(etapa,ord))))
  into v_salida;
  return v_salida;
end;
$function$
;

revoke all on function crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean) from public, anon, authenticated, service_role;
grant execute on function crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean) to authenticated;
comment on function crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean) is
  'Inventario de Leads con filtros comunes, incluido reasignados: titular actual con una asignacion anterior a un analista. Sistema/Manual conserva el alta. Filas, totales y embudo desde la misma base, bajo RLS.';

update private.analitica_leads_citas_exenciones e set
  objeto = 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean)',
  huella = '1e2cdd16e5d59f2dd6a8280052312009',
  razon = 'Inventario operativo unico para listado y resumen: filtros de etapa, analista, busqueda, recepcion, origen, procedencia y reasignacion entre analistas. No calcula conversion mensual.'
where e.objeto = 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)';
update private.analitica_lc_sello
  set sello = private.huella_exenciones_analitica_lc(), sellado_en = now()
  where id;

do $postflight$
declare
  f12 constant text := 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean)';
  f13 constant text := 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)';
  f12_larga constant text := 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean)';
  pre record;
begin
  select * into strict pre from pg_temp.cartera_gestion_reversa;
  if (
    to_regprocedure(f13) is null
    and to_regprocedure(f12) is not null
    and (select count(*) from pg_proc where proname = 'cartera_filtrada_fn'
           and pronamespace = 'crm'::regnamespace) = 1
    and md5(pg_get_functiondef(to_regprocedure(f12))) = '7169d94239dcb191bafa3faed46f916f'
    and not has_function_privilege('anon', f12, 'EXECUTE')
    and not has_function_privilege('service_role', f12, 'EXECUTE')
    and has_function_privilege('authenticated', f12, 'EXECUTE')
    and (select to_jsonb(p) from (select proowner::regrole::text as duenio,
            prosecdef, provolatile, proconfig, proacl
          from pg_proc where oid = to_regprocedure(f12)) p) = pre.contrato
  ) is not true then
    raise exception 'REVERSA: la funcion restaurada no es byte a byte la de 12 argumentos, o cambio su contrato';
  end if;
  if (
    (select s.sello from private.analitica_lc_sello s where s.id)
      = private.huella_exenciones_analitica_lc()
    and (select count(*) from private.contadores_crudos_leads_citas()) = pre.censo
    and exists (select 1 from private.contadores_crudos_leads_citas() c
                 where c.objeto = f12_larga and c.declarada and c.huella_ok)
    and (select coalesce(string_agg(c.objeto, ',' order by c.objeto), '')
           from private.contadores_crudos_leads_citas() c
          where not (c.declarada and c.huella_ok)) = pre.censo_rojo
    and (select jsonb_agg(to_jsonb(e) order by e.objeto)
           from private.analitica_leads_citas_exenciones e
          where e.objeto <> f12_larga) is not distinct from pre.otras
    and (select to_jsonb(e) - 'objeto' - 'huella' - 'razon'
           from private.analitica_leads_citas_exenciones e
          where e.objeto = f12_larga) = pre.declaracion
    and md5(pg_get_functiondef('crm.resumen_cartera_fn()'::regprocedure)) = pre.resumen_md5
  ) is not true then
    raise exception 'REVERSA: el censo analitico, una declaracion o un consumidor ajeno no quedo como estaba';
  end if;
  raise notice 'REVERSA cartera_filtro_gestion OK: vuelve la firma de 12 argumentos (md5 7169d94239dcb191bafa3faed46f916f) con su declaracion, sellada.';
end;
$postflight$;
notify pgrst, 'reload schema';
commit;
