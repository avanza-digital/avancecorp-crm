-- Gestionado en ficha y listados: lectura operativa por lote.
-- Autorizado por Miguel el 03/10/2026: «Sí, probar y publicar todo».
-- Sin escrituras de datos, tablas/policies nuevas ni cambios de etapas/SLA.
-- Reversa: frontend anterior, después DROP de puerta y núcleo en migración separada.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $preflight$
begin
  if not exists (select 1 from pg_class where oid = 'crm.leads'::regclass and relrowsecurity)
     or not exists (select 1 from pg_class where oid = 'crm.actividades'::regclass and relrowsecurity) then
    raise exception 'Gestionado requiere RLS activa en leads y actividades';
  end if;
  perform private.assert_actividades_de_lead_base();
end;
$preflight$;

create function private.gestion_vigente_lectura(p_lead_ids uuid[])
returns jsonb language plpgsql stable security invoker set search_path = '' as $$
declare v_salida jsonb;
begin
  if (select auth.uid()) is null or private.puede_acceder_crm() is not true then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if p_lead_ids is null or cardinality(p_lead_ids) > 100 or array_ndims(p_lead_ids) > 1
     then
    raise exception 'Lista de leads inválida' using errcode = '22023';
  end if;
  if array_position(p_lead_ids, null) is not null then
    raise exception 'Lista de leads inválida' using errcode = '22023';
  end if;
  select jsonb_build_object('version', 1, 'items',
    coalesce(jsonb_agg(jsonb_build_object(
      'lead_id', l.id, 'vendedor_id', l.vendedor_id,
      'tenencia_desde', l.tenencia_desde,
      'gestion_vigente', l.vendedor_id is not null
        and l.tenencia_desde is not null and exists (
          select 1 from crm.actividades a
          where a.lead_id = l.id and a.creado_en >= l.tenencia_desde
            and a.tipo in ('llamada_realizada', 'llamada_no_contestada',
              'whatsapp_enviado', 'whatsapp_recibido', 'reunion_realizada')
            and a.metadata -> 'deshecho_en' is null
        )
    ) order by l.id), '[]'::jsonb)) into v_salida
  from crm.leads l
  where l.id = any(p_lead_ids) and l.activo and l.etapa = 'nuevo';
  return v_salida;
end;
$$;
create function crm.gestion_vigente_fn(p_lead_ids uuid[])
returns jsonb language sql stable security invoker set search_path = '' as $$
  select private.gestion_vigente_lectura(p_lead_ids);
$$;
alter function private.gestion_vigente_lectura(uuid[]) owner to postgres;
alter function crm.gestion_vigente_fn(uuid[]) owner to postgres;
revoke all on function private.gestion_vigente_lectura(uuid[]) from public, anon, service_role;
revoke all on function crm.gestion_vigente_fn(uuid[]) from public, anon, service_role;
grant execute on function private.gestion_vigente_lectura(uuid[]) to authenticated;
grant execute on function crm.gestion_vigente_fn(uuid[]) to authenticated;
comment on function private.gestion_vigente_lectura(uuid[]) is
  'Lectura operativa de gestión vigente de nuevos: contacto no deshecho desde la tenencia actual; RLS del actor, lote máximo 100, sin datos de contacto.';
comment on function crm.gestion_vigente_fn(uuid[]) is
  'Puerta de lectura por lote para la etiqueta Gestionado; delega al núcleo privado y conserva RLS.';
do $postflight$
begin
  if exists (select 1 from pg_proc p
    where p.oid in ('private.gestion_vigente_lectura(uuid[])'::regprocedure, 'crm.gestion_vigente_fn(uuid[])'::regprocedure)
      and (p.prosecdef or p.provolatile <> 's' or not ('search_path=""' = any(p.proconfig))))
    or not has_function_privilege('authenticated', 'crm.gestion_vigente_fn(uuid[])', 'execute')
    or has_function_privilege('anon', 'crm.gestion_vigente_fn(uuid[])', 'execute')
    or has_function_privilege('service_role', 'crm.gestion_vigente_fn(uuid[])', 'execute') then
    raise exception 'Contrato de seguridad de Gestionado inválido';
  end if;
end;
$postflight$;
notify pgrst, 'reload schema';
commit;
