-- REVERSA de 20261003162500_crm_base_gestion_seguimiento_activo (B6): quita el candado, reinstala el cuerpo vivo de crm.rescate_descartes_mes (sin las columnas
-- en_gestion_*) y borra las dos funciones. La pantalla tolera la ausencia de las columnas. No toca datos.
begin;
set local lock_timeout = '10s';
set local search_path = '';
set local quote_all_identifiers = off;
do $pre$
begin
  if (
    (select md5(p.prosrc) = 'd21ca8325c777fb207d5f58df751748f' from pg_proc p where p.oid = to_regprocedure('crm.rescate_descartes_mes(date)'))
    and (select md5(p.prosrc) = 'af0701a9e095e1004a64b7e289789d7c' from pg_proc p where p.oid = to_regprocedure('private.base_gestion_en_gestion_hasta(uuid)'))
    and (select md5(p.prosrc) = 'dbdc8740d9f68a523e7b5afb54d2d774' from pg_proc p where p.oid = to_regprocedure('private.trg_leads_guard_seguimiento_activo()'))
  ) is not true then
    raise exception 'REVERSA: los cuerpos vivos no son los de B6';
  end if;
end;
$pre$;
drop trigger trg_leads_00_seguimiento_activo on crm.leads;
drop function private.trg_leads_guard_seguimiento_activo();
drop function crm.rescate_descartes_mes(date);
create function crm.rescate_descartes_mes(p_mes date)
 RETURNS TABLE(episodio_id uuid, lead_id uuid, nombre_completo text, distrito text, origen text, categoria_interes text, monto_estimado numeric, moneda text, motivo_descarte text, descartado_en timestamp with time zone, asesor_id uuid, asesor_nombre text, puede_rescatar boolean, estado text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := (select auth.uid());
  v_rol text;
  v_mes date := pg_catalog.date_trunc('month', p_mes)::date;
begin
  if p_mes is null then
    raise exception 'El mes es obligatorio' using errcode = '22023';
  end if;

  select e.rol_crm
    into v_rol
  from crm.equipo e
  join public.perfiles p on p.id = e.perfil_id
  where e.perfil_id = v_actor
    and e.activo = true
    and p.activo = true
    and e.rol_crm in ('supervisor', 'gerencia');

  if v_actor is null or v_rol is null then
    raise exception 'Solo supervisión puede consultar Base para gestión'
      using errcode = '42501';
  end if;

  return query
  select
    la.id as episodio_id,
    l.id as lead_id,
    l.nombre_completo,
    l.distrito,
    la.origen,
    la.categoria_interes,
    la.monto_estimado,
    la.moneda,
    la.motivo_descarte_cierre,
    la.resultado_en,
    la.analista_id,
    p_asesor.nombre_completo,
    (
      l.activo = true
      and l.etapa = 'descartado'
      and l.descartado_en is not distinct from la.resultado_en
      and la.motivo_descarte_cierre <> 'datos_invalidos'
      and l.no_contactar is not true
    ) as puede_rescatar,
    case
      when l.activo = true
       and l.etapa = 'descartado'
       and l.descartado_en is not distinct from la.resultado_en
       and la.motivo_descarte_cierre <> 'datos_invalidos'
       and l.no_contactar is not true
        then 'pendiente'
      when exists (
        select 1
        from crm.lead_asignaciones la_posterior
        where la_posterior.lead_id = la.lead_id
          and la_posterior.asignado_en > la.resultado_en
      ) then 'rescatado'
      else 'historial'
    end as estado
  from crm.lead_asignaciones la
  join crm.leads l on l.id = la.lead_id
  join public.perfiles p_asesor on p_asesor.id = la.analista_id
  where la.resultado = 'descartado'
    and la.resultado_en is not null
    and la.resultado_en >= (v_mes::timestamp at time zone 'America/Lima')
    and la.resultado_en < ((v_mes + interval '1 month')::timestamp at time zone 'America/Lima')
    and (
      v_rol = 'gerencia'
      or la.analista_id in (
        select private.vendedor_ids_visibles(v_actor)
      )
    )
  order by la.resultado_en desc, la.id desc;
end;
$function$;
alter function crm.rescate_descartes_mes(date) owner to postgres;
revoke all on function crm.rescate_descartes_mes(date) from public, anon, authenticated, service_role;
grant execute on function crm.rescate_descartes_mes(date) to authenticated;
comment on function crm.rescate_descartes_mes(date) is 'Historial mensual sin PII de contacto para Base para gestión. Cada fila es un episodio inmutable del ledger, no el estado actual mutable del lead.';
drop function private.base_gestion_en_gestion_hasta(uuid);
do $post$
begin
  if (select md5(p.prosrc) = '7c6363fbc96bc51f14997196e6eb8661' and p.proacl::text = '{postgres=X/postgres,authenticated=X/postgres}' from pg_proc p where p.oid = to_regprocedure('crm.rescate_descartes_mes(date)')) is not true
     or exists (select 1 from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_00_seguimiento_activo') then
    raise exception 'REVERSA: el rescate restaurado no es el vivo del 03/10 o el candado sigue';
  end if;
end;
$post$;
notify pgrst, 'reload schema';
commit;
