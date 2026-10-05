-- REVERSA de 20261004045038_crm_base_gestion_ver_vetados (B6b): borra crm.base_gestion_resumen_detalle(uuid, text) y reinstala
-- crm.obtener_base_gestion(uuid) con la firma, el cuerpo, el dueño, la ACL y el comentario EXACTOS de B5 (20261003162400,
-- md5 b2629fba…). No toca datos. La pantalla de F4 (rama crm/base-gestion-f4) tolera la ausencia: si el servidor responde
-- PGRST202 reintenta sin p_incluir_vetados y no abre el interruptor ni las cifras. Antes de revertir B5 o anteriores, esta.
begin;
set transaction isolation level repeatable read;  -- como la migración: una sola instantánea
set local lock_timeout = '10s';
set local search_path = '';
set local quote_all_identifiers = off;
do $pre$
begin
  if (
    (select md5(p.prosrc) = '36af7e9cc4d6ec319b3d8004f3903473' from pg_proc p where p.oid = to_regprocedure('crm.obtener_base_gestion(uuid,boolean)'))
    and (select md5(p.prosrc) = '068372248be4127c80ba002542c9b4b8' from pg_proc p where p.oid = to_regprocedure('crm.base_gestion_resumen_detalle(uuid,text)'))
    and to_regprocedure('crm.obtener_base_gestion(uuid)') is null
  ) is not true then
    raise exception 'REVERSA: los cuerpos vivos no son los de B6b (o B6b no esta aplicada)';
  end if;
end;
$pre$;
drop function crm.base_gestion_resumen_detalle(uuid, text);
drop function crm.obtener_base_gestion(uuid, boolean);
create function crm.obtener_base_gestion(p_vendedor_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(lead_id uuid, nombre_completo text, telefono text, distrito text, origen text, categoria_interes text, monto_estimado numeric, moneda text, motivo_descarte text, descartado_en timestamp with time zone, dias_desde_descarte integer, etapa_maxima text, intentos integer, ultimo_resultado text, ultimo_intento_en timestamp with time zone, proxima_llamada_en timestamp with time zone, rellamada_hoy boolean, enfriado_hasta date, ciclo_n integer, vendedor_id uuid, gestiona text, recibido_en timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text;
  v_hoy date := (now() at time zone 'America/Lima')::date;
begin
  v_rol := private.base_gestion_rol(v_uid);
  if p_vendedor_id is not null then
    if v_rol = 'vendedor' and p_vendedor_id <> v_uid then
      raise exception 'Un analista solo consulta su propia base' using errcode = '42501';
    end if;
    if v_rol = 'supervisor' and p_vendedor_id not in (select private.vendedor_ids_visibles(v_uid)) then
      raise exception 'Analista no encontrado o fuera de tu ambito' using errcode = 'P0002';
    end if;
  end if;
  return query
  with base as (
    select l.id, l.nombre_completo, l.telefono, l.distrito, l.origen, l.categoria_interes, l.monto_estimado, l.moneda,
           l.motivo_descarte, l.descartado_en, l.proxima_llamada_en, l.enfriado_hasta, l.ciclo_actual, l.vendedor_id,
           coalesce(l.tenencia_desde, l.creado_en) as recibido_en,  -- B5: cuando le llego el lead a quien lo tiene (el MES del lead)
           private.base_gestion_intentos_desde(l.descartado_en, l.creado_en, l.enfriado_hasta, v_hoy) as desde  -- D13: ventana desde el descarte o desde el fin del ultimo descanso
    from crm.leads l
    where l.activo and l.etapa = 'descartado' and not l.no_contactar
      and (l.enfriado_hasta is null or l.enfriado_hasta <= v_hoy)
      and private.base_gestion_lead_visible(v_uid, v_rol, l.vendedor_id, l.asignado_supervisor_id)
      and (p_vendedor_id is null or l.vendedor_id = p_vendedor_id)
  ),
  intentos as (
    -- B3c: contador, último resultado (desempate por intento_n, Codex B3 #5) y último intento salen de la MISMA definición
    -- que usan el núcleo y el enfriamiento: private.base_gestion_intentos_ciclo, con la ventana D13 de cada lead.
    select c.lead_id, c.n, c.ultimo, c.ultimo_en
    from (select array_agg(b.id order by b.id) as ids, array_agg(b.desde order by b.id) as desdes from base b) q
    cross join lateral private.base_gestion_intentos_ciclo(q.ids, q.desdes) c
  ),
  ciclo as (
    -- El ciclo vigente empieza en la ultima reapertura (cambio_etapa descartado → nuevo) o, si nunca hubo, al inicio.
    -- Se acota con el propio historial (misma fuente y mismo reloj que los cambios de etapa): robusto frente a
    -- transacciones multi-sentencia, donde now() del log y statement_timestamp() del ledger difieren.
    select b.id as lead_id,
           coalesce((select max(a.creado_en) from crm.actividades a
                      where a.lead_id = b.id and a.tipo = 'cambio_etapa' and a.metadata->>'etapa_anterior' = 'descartado'),
                    '-infinity'::timestamptz) as desde
    from base b
  ),
  etapas as (
    select a.lead_id,
           max(greatest(private.base_gestion_etapa_rango(a.metadata->>'etapa_anterior'),
                        private.base_gestion_etapa_rango(case when a.metadata->>'etapa_nueva' <> 'descartado' then a.metadata->>'etapa_nueva' end))) as rango
    from crm.actividades a join ciclo c on c.lead_id = a.lead_id
    where a.tipo = 'cambio_etapa' and a.creado_en >= c.desde
      -- Codex B3 #6: el descarte del ciclo anterior puede compartir instante con la reapertura (misma transaccion): fuera.
      and not (a.creado_en = c.desde and a.metadata->>'etapa_nueva' = 'descartado')
    group by a.lead_id
  )
  select b.id, b.nombre_completo, b.telefono, b.distrito, b.origen, b.categoria_interes, b.monto_estimado, b.moneda,
         b.motivo_descarte, b.descartado_en,
         case when b.descartado_en is null then null else (v_hoy - (b.descartado_en at time zone 'America/Lima')::date)::integer end,
         case coalesce(e.rango, 0) when 1 then 'nuevo' when 2 then 'contactado' when 3 then 'reunion_agendada'
                                   when 4 then 'propuesta_enviada' when 5 then 'convertido' else 'sin_datos' end,
         coalesce(i.n, 0), i.ultimo, i.ultimo_en,
         b.proxima_llamada_en,
         (b.proxima_llamada_en is not null and (b.proxima_llamada_en at time zone 'America/Lima')::date <= v_hoy),
         b.enfriado_hasta, b.ciclo_actual, b.vendedor_id, p.nombre_completo, b.recibido_en
  from base b
  left join intentos i on i.lead_id = b.id
  left join etapas e on e.lead_id = b.id
  left join public.perfiles p on p.id = b.vendedor_id
  -- Contrato (encargo): rellamada vencida o de hoy → etapa maxima (desc) → dias desde el descarte (asc); la hora de la
  -- rellamada solo desempata (Codex B3 #4).
  order by (b.proxima_llamada_en is not null and (b.proxima_llamada_en at time zone 'America/Lima')::date <= v_hoy) desc,
           coalesce(e.rango, 0) desc,
           (b.descartado_en at time zone 'America/Lima')::date desc nulls last,  -- menos dias desde el descarte primero
           b.proxima_llamada_en asc nulls last,
           b.id;
end;
$function$;
alter function crm.obtener_base_gestion(uuid) owner to postgres;
revoke all on function crm.obtener_base_gestion(uuid) from public, anon, authenticated, service_role;
grant execute on function crm.obtener_base_gestion(uuid) to authenticated;
comment on function crm.obtener_base_gestion(uuid) is 'Base para gestión (B3): leads descartados vivos del ámbito del actor (analista → los suyos; Supervisión → subárbol; Gerencia → todo), sin «no contactar» ni descanso vigente, con intentos del ciclo, último resultado, próxima rellamada, etapa máxima alcanzada y quién gestiona. Orden: rellamada vencida o de hoy → etapa máxima → menos días desde el descarte. p_vendedor_id filtra un analista dentro del ámbito. DEFINER: ámbito explícito (espejo de leads_select), search_path vacío, EXECUTE solo authenticated. B3c (03/10/2026): sus conteos de intentos salen de private.base_gestion_intentos_ciclo; fuera del censo analítico. B5 (03/10/2026): devuelve al final recibido_en = coalesce(tenencia_desde, creado_en), cuándo le llegó el lead a quien lo tiene: el MES por el que se organiza el analista.';
do $post$
begin
  if (
    (select md5(p.prosrc) = 'b2629fba517938457b64cdbc5856ee82'
        and p.proargnames[pg_catalog.array_length(p.proargnames, 1)] = 'recibido_en'
        and p.prosecdef and p.provolatile = 's' and p.proowner = 'postgres'::regrole
        and p.proconfig = array['search_path=""']::text[] and p.proacl::text = '{postgres=X/postgres,authenticated=X/postgres}'
       from pg_proc p where p.oid = to_regprocedure('crm.obtener_base_gestion(uuid)'))
    and obj_description(to_regprocedure('crm.obtener_base_gestion(uuid)'), 'pg_proc') like '%B5 (03/10/2026)%'
    and obj_description(to_regprocedure('crm.obtener_base_gestion(uuid)'), 'pg_proc') not like '%B6b%'
    and (select count(*) = 1 from pg_proc p where p.proname = 'obtener_base_gestion' and p.pronamespace = 'crm'::regnamespace)
    and to_regprocedure('crm.base_gestion_resumen_detalle(uuid,text)') is null
    and (select md5(p.prosrc) = 'b773a7c49fbdfc45133b3405991b1958' from pg_proc p where p.oid = to_regprocedure('crm.base_gestion_resumen()'))
    and not exists (select 1 from private.contadores_crudos_leads_citas() c where c.objeto = to_regprocedure('crm.obtener_base_gestion(uuid)')::text)
  ) is not true then
    raise exception 'REVERSA: obtener_base_gestion no quedo como en B5 o la detalle sigue';
  end if;
  raise notice 'reversa B6b OK: obtener_base_gestion(uuid) = B5, sin la detalle';
end;
$post$;
notify pgrst, 'reload schema';
commit;
