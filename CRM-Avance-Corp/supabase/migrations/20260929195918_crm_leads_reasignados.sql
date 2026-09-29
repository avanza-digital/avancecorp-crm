-- Reasignados en Leads: un lead con analista actual que ya estuvo en
-- manos de un analista antes de un reparto posterior. Sistema/Manual sigue describiendo el alta y no se
-- sobrescribe. La misma base filtrada produce filas y cifras antes de paginar.
-- La lectura de actividades es INVOKER y hereda la RLS coextensiva con leads.
-- Reversa coordinada: retirar la firma de 12 argumentos, reinstalar la de 11
-- desde 20260919170500_crm_cartera_filtro_procedencia.sql, mover de vuelta su
-- exencion analitica y resellar; publicar el frontend anterior en el mismo corte.
begin;
set local lock_timeout='10s';
set local statement_timeout='30s';

lock table private.analitica_leads_citas_exenciones,
  private.analitica_lc_sello in share row exclusive mode;

do $preflight$
begin
  if to_regprocedure('crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean)') is not null
     or (select count(*) from pg_proc where proname='cartera_filtrada_fn'
           and pronamespace='crm'::regnamespace) <> 1
     or md5(pg_get_functiondef('crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text)'::regprocedure))
       is distinct from '815b834162ff1acbb613d4a40f6e6996' then
    raise exception 'PREFLIGHT: cartera_filtrada_fn no coincide con la version auditada';
  end if;
  if not exists(select 1 from private.contadores_crudos_leads_citas()
      where objeto='crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text)' and declarada and huella_ok)
     or (select clase from private.analitica_leads_citas_exenciones
           where objeto='crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text)') is distinct from 'operativo'
     or (select sello from private.analitica_lc_sello where id)
           is distinct from private.huella_exenciones_analitica_lc() then
    raise exception 'PREFLIGHT: la declaracion analitica no esta vigente y sellada';
  end if;
  perform private.assert_actividades_de_lead_base();
  -- El conteo se apoya en eventos del trigger, no en una marca editable.
  -- Fallar si la fuente dejo de emitirlos o si una policy permite falsificarlos.
  if not exists(select 1 from pg_trigger t
      where t.tgrelid='crm.leads'::regclass
        and t.tgname='trg_leads_reasignacion' and t.tgenabled='O'
        and md5(pg_get_triggerdef(t.oid))='860de32bfda93b457ec3150fc1286121'
        and md5(pg_get_functiondef(t.tgfoid))='ed73407e78b20e850f11d688774c8846')
     or (select count(*) from pg_policy p
           where p.polrelid='crm.actividades'::regclass and p.polcmd='a') <> 1
     or not exists(select 1 from pg_policy p
           where p.polrelid='crm.actividades'::regclass and p.polcmd='a'
             and p.polname='actividades_insert' and p.polpermissive
             and p.polroles=array['authenticated'::regrole::oid]
             and md5(pg_get_expr(p.polwithcheck,p.polrelid))='b2d6792bc6913861ca74f4398e6a12ab')
     -- Una policy ALL permisiva se combinaría por OR con actividades_insert.
     -- UPDATE/DELETE permitirían cambiar o borrar eventos ya emitidos.
     or exists(select 1 from pg_policy p
           where p.polrelid='crm.actividades'::regclass
             and ((p.polcmd='*' and p.polpermissive) or p.polcmd in ('w','d')))
     or has_any_column_privilege('authenticated','crm.actividades','UPDATE')
     or has_table_privilege('authenticated','crm.actividades','DELETE')
     or has_any_column_privilege('anon','crm.actividades','UPDATE')
     or has_table_privilege('anon','crm.actividades','DELETE') then
    raise exception 'PREFLIGHT: fuente de reasignaciones no coincide con la version auditada';
  end if;
end;
$preflight$;

create temporary table cartera_reasignados_preflight on commit drop as
select
  (select to_jsonb(p) from (select proowner::regrole::text as duenio,
      prosecdef, provolatile, proconfig, proacl
    from pg_proc where oid='crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text)'::regprocedure) p) as contrato,
  (select count(*) from private.contadores_crudos_leads_citas()) as censo,
  (select coalesce(string_agg(objeto,',' order by objeto),'')
    from private.contadores_crudos_leads_citas()
    where not (declarada and huella_ok)) as censo_rojo,
  (select jsonb_agg(to_jsonb(e) order by objeto)
    from private.analitica_leads_citas_exenciones e
    where objeto <> 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text)') as otras,
  md5(pg_get_functiondef('crm.resumen_cartera_fn()'::regprocedure)) as resumen_md5;

drop function crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text);

create function crm.cartera_filtrada_fn(
  p_limite integer default 50,
  p_antes_de timestamptz default null,
  p_antes_id uuid default null,
  p_etapa text default null,
  p_vendedor_id uuid default null,
  p_sin_asignar boolean default false,
  p_texto text default null,
  p_desde date default null,
  p_hasta date default null,
  p_origen text default null,
  p_procedencia text default null,
  p_reasignados boolean default false
)
returns jsonb language plpgsql stable security invoker set search_path = '' as $$
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
$$;

revoke all on function crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean) from public, anon, authenticated, service_role;
grant execute on function crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean) to authenticated;
comment on function crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean) is
  'Inventario de Leads con filtros comunes, incluido reasignados: titular actual con una asignacion anterior a un analista. Sistema/Manual conserva el alta. Filas, totales y embudo desde la misma base, bajo RLS.';

update private.analitica_leads_citas_exenciones e set
  objeto=p.oid::regprocedure::text,
  huella=md5(regexp_replace(regexp_replace(lower(p.prosrc),'--[^\n]*',' ','g'),'/\*.*?\*/',' ','g')),
  razon='Inventario operativo unico para listado y resumen: filtros de etapa, analista, busqueda, recepcion, origen, procedencia y reasignacion entre analistas. No calcula conversion mensual.'
from pg_proc p
where p.oid='crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean)'::regprocedure
  and e.objeto='crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text)';
update private.analitica_lc_sello
  set sello=private.huella_exenciones_analitica_lc(), sellado_en=now()
  where id;

do $postflight$
declare
  f text := 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean)';
begin
  if to_regprocedure('crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text)') is not null
     or (select count(*) from pg_proc where proname='cartera_filtrada_fn'
          and pronamespace='crm'::regnamespace) <> 1
     or has_function_privilege('anon',f,'EXECUTE')
     or has_function_privilege('service_role',f,'EXECUTE')
     or not has_function_privilege('authenticated',f,'EXECUTE')
     or (select to_jsonb(p) from (select proowner::regrole::text as duenio,
          prosecdef, provolatile, proconfig, proacl
        from pg_proc where oid=to_regprocedure(f)) p)
          is distinct from (select contrato from cartera_reasignados_preflight)
     or (select sello from private.analitica_lc_sello where id)
          is distinct from private.huella_exenciones_analitica_lc() then
    raise exception 'POSTFLIGHT: firma, ACL o sello invalido';
  end if;
  if (select count(*) from private.contadores_crudos_leads_citas())
       <> (select censo from cartera_reasignados_preflight)
     or not exists(select 1 from private.contadores_crudos_leads_citas()
       where objeto=to_regprocedure(f)::text and declarada and huella_ok)
     or (select coalesce(string_agg(objeto,',' order by objeto),'')
          from private.contadores_crudos_leads_citas()
          where not (declarada and huella_ok))
       <> (select censo_rojo from cartera_reasignados_preflight)
     or (select jsonb_agg(to_jsonb(e) order by objeto)
          from private.analitica_leads_citas_exenciones e
          where objeto <> to_regprocedure(f)::text)
       is distinct from (select otras from cartera_reasignados_preflight)
     or md5(pg_get_functiondef('crm.resumen_cartera_fn()'::regprocedure))
       is distinct from (select resumen_md5 from cartera_reasignados_preflight) then
    raise exception 'POSTFLIGHT: cambio un contador o consumidor ajeno';
  end if;
  perform private.assert_actividades_de_lead_base();
  if not exists(select 1 from pg_trigger t
      where t.tgrelid='crm.leads'::regclass
        and t.tgname='trg_leads_reasignacion' and t.tgenabled='O'
        and md5(pg_get_triggerdef(t.oid))='860de32bfda93b457ec3150fc1286121'
        and md5(pg_get_functiondef(t.tgfoid))='ed73407e78b20e850f11d688774c8846')
     or (select count(*) from pg_policy p
           where p.polrelid='crm.actividades'::regclass and p.polcmd='a') <> 1
     or not exists(select 1 from pg_policy p
           where p.polrelid='crm.actividades'::regclass and p.polcmd='a'
             and p.polname='actividades_insert' and p.polpermissive
             and p.polroles=array['authenticated'::regrole::oid]
             and md5(pg_get_expr(p.polwithcheck,p.polrelid))='b2d6792bc6913861ca74f4398e6a12ab')
     or exists(select 1 from pg_policy p
           where p.polrelid='crm.actividades'::regclass
             and ((p.polcmd='*' and p.polpermissive) or p.polcmd in ('w','d')))
     or has_any_column_privilege('authenticated','crm.actividades','UPDATE')
     or has_table_privilege('authenticated','crm.actividades','DELETE')
     or has_any_column_privilege('anon','crm.actividades','UPDATE')
     or has_table_privilege('anon','crm.actividades','DELETE') then
    raise exception 'POSTFLIGHT: fuente de reasignaciones cambio';
  end if;
end;
$postflight$;
notify pgrst,'reload schema';
commit;
