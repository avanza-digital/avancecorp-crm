-- Reversa de la procedencia: retira la firma de 11 argumentos y restaura la
-- de 10 publicada el 16/09 (definición tomada del banco a paridad con producción,
-- md5 be33021420cd8ae2edbf58692b45e9eb) con su declaración analítica original.
-- Ejecutar solo tras retirar el frontend que envía p_procedencia (las pestañas
-- ya abiertas conservan su JavaScript hasta recargar: pueden seguir enviándolo).
-- Guardas: no retira una función corregida después de esta entrega ni re-sella
-- una lista de exenciones alterada por fuera. No toca datos.
-- GENERADO por supabase/scripts/cartera-procedencia/generar-reversa.mjs; no editar a mano.
begin;
set local lock_timeout='10s';
lock table private.analitica_leads_citas_exenciones,private.analitica_leads_citas_tope,
  private.analitica_lc_sello in share row exclusive mode;
do $preflight$
begin
  if to_regprocedure('crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text)') is null
     or (select count(*) from pg_proc where proname='cartera_filtrada_fn' and pronamespace='crm'::regnamespace)<>1 then
    raise exception 'REVERSA: la firma de 11 argumentos no es la única instalada';
  end if;
  -- Exactamente la función publicada por 20260919170500 (md5 de la definición y
  -- huella del censo medidos al ensayarla); una corrección posterior no se pisa.
  if md5(pg_get_functiondef('crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text)'::regprocedure)) is distinct from '815b834162ff1acbb613d4a40f6e6996'
     or (select huella from private.analitica_leads_citas_exenciones where objeto='crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text)')
        is distinct from '8d24207266a2a31829116c6105b01597'
     or not exists (select 1 from private.contadores_crudos_leads_citas()
        where objeto='crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text)' and declarada and huella_ok) then
    raise exception 'REVERSA: la función de 11 argumentos no es la publicada por 20260919170500';
  end if;
  if (select sello from private.analitica_lc_sello where id) is distinct from private.huella_exenciones_analitica_lc() then
    raise exception 'REVERSA: la lista de exenciones no coincide con su sello; no se re-sella a ciegas';
  end if;
end;
$preflight$;
create temporary table cartera_procedencia_reversa on commit drop as
select (select jsonb_agg(to_jsonb(e) order by objeto) from private.analitica_leads_citas_exenciones e
    where objeto<>'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text)') as otras,
  (select to_jsonb(t) from private.analitica_leads_citas_tope t where id) as tope,
  (select proacl from pg_proc where oid='crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text)'::regprocedure) as acl,
  (select count(*) from private.contadores_crudos_leads_citas()) as censo,
  (select coalesce(string_agg(objeto,',' order by objeto),'') from private.contadores_crudos_leads_citas()
    where not (declarada and huella_ok)) as censo_rojo,
  md5(pg_get_functiondef('crm.resumen_cartera_fn()'::regprocedure)) as resumen_md5;

drop function crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text);
CREATE OR REPLACE FUNCTION crm.cartera_filtrada_fn(p_limite integer DEFAULT 50, p_antes_de timestamp with time zone DEFAULT NULL::timestamp with time zone, p_antes_id uuid DEFAULT NULL::uuid, p_etapa text DEFAULT NULL::text, p_vendedor_id uuid DEFAULT NULL::uuid, p_sin_asignar boolean DEFAULT false, p_texto text DEFAULT NULL::text, p_desde date DEFAULT NULL::date, p_hasta date DEFAULT NULL::date, p_origen text DEFAULT NULL::text)
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
      r.recibido_en, coalesce(r.aproximado,false) as recepcion_aproximada
    from crm.leads l
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
    'desde',p_desde,'hasta',p_hasta,'origen',p_origen,
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
revoke all on function crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text) from public, anon, authenticated, service_role;
grant execute on function crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text) to authenticated;
comment on function crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text) is 'Leads e indicadores con filtros comunes: etapa, analista, búsqueda, recepción y origen. Recepción del analista actual, días inclusivos de Lima, un lead por resultado. RLS vigente y sin acceso a otros equipos. Sin fechas conserva inventario operativo de 45 días.';

-- La declaración analítica vuelve a la firma de 10 con su huella y razón del
-- 16/09 (fecha de declaración intacta) y se re-sella.
update private.analitica_leads_citas_exenciones e set
  objeto='crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text)',
  huella='d7a47e4c8377115178d75fc2bfcd35a2',
  razon='Inventario operativo único para listado y resumen: filtros de etapa, analista, búsqueda, recepción del dueño actual y origen del lead. No calcula conversión mensual: el adaptador general conserva el núcleo oficial.'
where e.objeto='crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text)';
update private.analitica_lc_sello set sello=private.huella_exenciones_analitica_lc(),sellado_en=now() where id;

do $postflight$
declare f text:='crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text)';
begin
  if md5(pg_get_functiondef(f::regprocedure)) is distinct from 'be33021420cd8ae2edbf58692b45e9eb' then
    raise exception 'REVERSA: la función restaurada no es byte a byte la del 16/09';
  end if;
  if not exists(select 1 from pg_proc p where p.oid=to_regprocedure(f)
      and p.proowner='postgres'::regrole and not p.prosecdef
      and p.provolatile='s' and p.proconfig @> array['search_path=""'])
    or has_function_privilege('anon',f,'EXECUTE')
    or has_function_privilege('service_role',f,'EXECUTE')
    or not has_function_privilege('authenticated',f,'EXECUTE')
    or (select proacl from pg_proc where oid=to_regprocedure(f))
       is distinct from (select acl from cartera_procedencia_reversa) then
    raise exception 'REVERSA: contrato de seguridad inválido para %',f;
  end if;
  if to_regprocedure('crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text)') is not null
    or (select count(*) from pg_proc where proname='cartera_filtrada_fn' and pronamespace='crm'::regnamespace)<>1 then
    raise exception 'REVERSA: la firma de 11 sigue instalada';
  end if;
  if (select count(*) from private.contadores_crudos_leads_citas())
       <> (select censo from cartera_procedencia_reversa)
    or not exists (select 1 from private.contadores_crudos_leads_citas()
       where objeto='crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text)' and declarada and huella_ok)
    or (select coalesce(string_agg(objeto,',' order by objeto),'') from private.contadores_crudos_leads_citas()
       where not (declarada and huella_ok)) <> (select censo_rojo from cartera_procedencia_reversa)
    or (select sello from private.analitica_lc_sello where id) is distinct from private.huella_exenciones_analitica_lc() then
    raise exception 'REVERSA: el censo analítico no quedó como se esperaba';
  end if;
  if (select jsonb_agg(to_jsonb(e) order by objeto) from private.analitica_leads_citas_exenciones e
      where objeto<>'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text)')
       is distinct from (select otras from cartera_procedencia_reversa)
    or (select to_jsonb(t) from private.analitica_leads_citas_tope t where id)
       is distinct from (select tope from cartera_procedencia_reversa)
    or md5(pg_get_functiondef('crm.resumen_cartera_fn()'::regprocedure))
       is distinct from (select resumen_md5 from cartera_procedencia_reversa) then
    raise exception 'REVERSA: cambió una declaración ajena, el techo o el resumen general';
  end if;
end;
$postflight$;
notify pgrst,'reload schema';
commit;
