-- Ficha individual: optimiza el núcleo canónico sin cambiar el contrato público.
-- Mantiene los controles de visibilidad al entrar y al terminar, datos y ACL existentes.
-- No modifica tablas, hechos económicos, banderas, RLS ni frontend.
begin;
do $precondiciones$
begin
  if to_regprocedure('private.cartera_f5_personas_visibles(uuid)') is not null then
    raise exception 'La variante individual ya existe; revisar la deriva antes de aplicar';
  end if;
  if md5(pg_get_functiondef('private.cartera_f5_personas_visibles()'::regprocedure))
      is distinct from '63a36c13296fd6337d63f298bcc2bc9e'
    or md5(pg_get_functiondef('crm.inversionista_ficha_fn(uuid,integer,integer)'::regprocedure))
      is distinct from 'd937fdc0f8515cc9f408324f707e19f1' then
    raise exception 'Cambió el núcleo o la ficha; revisar antes de optimizar';
  end if;
end;
$precondiciones$;

-- NULL solicita el conjunto completo; un UUID solicita su identidad canónica.
-- La ficha conserva además su filtro externo, incluso para entrada NULL.
CREATE OR REPLACE FUNCTION private.cartera_f5_personas_visibles(p_inversionista uuid)
 RETURNS TABLE(inversionista_id uuid, nombre text, documento_tipo text, documento text, documento_verificado boolean, telefono text, correo text, estado text, no_contactar boolean, responsable_id uuid, responsable_nombre text, perfil_id uuid, perfil_ids uuid[], lead_ids uuid[], creado_en timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with destino as materialized (
    -- Conserva aliases/fusiones: el filtro siempre se aplica a la identidad canónica.
    select private.inversionista_canonica(p_inversionista) id
  ), actor as materialized (
    select (select auth.uid()) uid,private.rol_crm((select auth.uid())) rol,
      private.es_lector_global() lector,
      array(select private.vendedor_ids_visibles((select auth.uid()))) visibles
  ), identidades as materialized (
    -- La resolución recursiva canónica sigue siendo la autoridad de las fusiones.
    select i.id,private.inversionista_canonica(i.id) canonica,i.perfil_id
    from crm.inversionistas i
  ), todas_fuentes as materialized (
    select * from private.cartera_f5_fuentes()
  ), fuentes as materialized (
    select * from todas_fuentes where es_demo is not true
  ), demos as materialized (
    select * from todas_fuentes where es_demo is true
  ), con_historia as materialized (
    select i.canonica id from demos f join identidades i on i.perfil_id=f.perfil_id
    union select i.canonica from demos f
      join crm.inversiones iv on iv.id=f.inversion_id
      join identidades i on i.id=iv.inversionista_id
    union select i.canonica from demos f
      join crm.cierres_externos ce on ce.id=f.fuente_id
      join identidades i on i.id=ce.inversionista_id
    union select i.canonica from demos f
      join crm.leads l on l.id=f.lead_id
      join identidades i on i.id=l.inversionista_id
    union select i.canonica from demos f
      join crm.inversionista_leads il on il.lead_id=f.lead_id
      join identidades i on i.id=il.inversionista_id
  ), perfiles_lector as materialized (
    select v.cliente_id from actor a
      cross join lateral private.cliente_ids_visibles_crm() v where a.lector
  ), perfiles_cliente as materialized (
    select i.canonica,p.id perfil_id from identidades i
      join public.perfiles p on p.id=i.perfil_id and p.rol='cliente'
  ), perfiles_enlazados as materialized (
    select p.canonica,array_agg(distinct p.perfil_id order by p.perfil_id) perfiles
    from perfiles_cliente p cross join actor a
    where not a.lector or exists(select 1 from perfiles_lector v where v.cliente_id=p.perfil_id)
    group by p.canonica
  ), leads_enlazados as materialized (
    select x.canonica,array_agg(x.lead_id order by x.lead_id) leads from (
      select i.canonica,l.id lead_id from crm.leads l
        join identidades i on i.id=l.inversionista_id
      union select i.canonica,il.lead_id from crm.inversionista_leads il
        join identidades i on i.id=il.inversionista_id
    ) x group by x.canonica
  ), bandeja_supervisor as materialized (
    select distinct i.canonica from crm.leads l
      join identidades i on i.id=l.inversionista_id cross join actor a
    where a.rol='supervisor' and l.activo and l.vendedor_id is null
      and l.asignado_supervisor_id=a.uid
  ), autorizadas as materialized (
    select i.*,a.lector from crm.inversionistas i cross join actor a
    where a.uid is not null and i.inversionista_canonico_id is null
      -- Recorta antes de los laterales de presentación; no elimina ninguna regla de acceso.
      and (p_inversionista is null or i.id=(select id from destino))
      and (a.rol in ('vendedor','supervisor','gerencia') or a.lector)
      and (a.rol='gerencia'
        or (not a.lector and i.responsable_relacion_id=any(a.visibles))
        or (a.rol='supervisor' and i.responsable_relacion_id is null
          and exists(select 1 from bandeja_supervisor b where b.canonica=i.id))
        or (a.lector and exists(select 1 from perfiles_enlazados p where p.canonica=i.id)))
      and (exists(select 1 from fuentes f where f.inversionista_id=i.id)
        or (not exists(select 1 from con_historia h where h.id=i.id)
          and exists(select 1 from perfiles_cliente p where p.canonica=i.id)))
  )
  select i.id,
    coalesce(nullif(btrim(p.nombre_completo),''),nullif(btrim(l.nombre_completo),''),
      nullif(btrim(ce.nombre_completo),''),'Identidad pendiente de completar'),
    case when i.lector then p.tipo_documento else d.tipo_documento end,
    case when i.lector then p.dni else d.documento_normalizado end,
    coalesce(d.verificado and (not i.lector or (d.tipo_documento=p.tipo_documento
      and d.documento_normalizado=p.dni)),false),
    coalesce(p.telefono,case when not i.lector then l.telefono end),
    coalesce(p.correo,case when not i.lector then l.correo end),
    i.estado,i.no_contactar or coalesce(l.no_contactar,false),
    i.responsable_relacion_id,r.nombre_completo,i.perfil_id,
    coalesce(pe.perfiles,'{}'::uuid[]),coalesce(le.leads,'{}'::uuid[]),i.creado_en
  from autorizadas i
  left join public.perfiles r on r.id=i.responsable_relacion_id
  left join perfiles_enlazados pe on pe.canonica=i.id
  left join leads_enlazados le on le.canonica=i.id
  left join lateral (
    select p0.* from public.perfiles p0 where p0.id=any(pe.perfiles)
      and (not i.lector or p0.rol='cliente')
    order by (p0.id=i.perfil_id) desc,p0.activo desc,p0.id limit 1
  ) p on true
  left join lateral (
    select l0.* from crm.leads l0 where l0.id=any(le.leads) and not i.lector
    order by (l0.inversionista_id=i.id) desc,l0.actualizado_en desc,l0.id limit 1
  ) l on true
  left join lateral (
    select ce0.nombre_completo from crm.cierres_externos ce0
      join fuentes f on f.fuente_id=ce0.id and f.empresa<>'avance'
    where f.inversionista_id=i.id and not i.lector
    order by ce0.creado_en desc,ce0.id limit 1
  ) ce on true
  left join lateral (
    select d0.* from crm.inversionista_identificadores d0
    where d0.inversionista_id=i.id and d0.estado='vigente'
    order by d0.verificado desc,
      case d0.tipo_documento when 'DNI' then 1 when 'CE' then 2 else 3 end,d0.id
    limit 1
  ) d on true;
$function$
;

alter function private.cartera_f5_personas_visibles(uuid) owner to postgres;
revoke all on function private.cartera_f5_personas_visibles(uuid)
  from public, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION private.cartera_f5_personas_visibles()
 RETURNS TABLE(inversionista_id uuid, nombre text, documento_tipo text, documento text, documento_verificado boolean, telefono text, correo text, estado text, no_contactar boolean, responsable_id uuid, responsable_nombre text, perfil_id uuid, perfil_ids uuid[], lead_ids uuid[], creado_en timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- Firma histórica: el listado y sus consumidores conservan el mismo núcleo.
  select * from private.cartera_f5_personas_visibles(null::uuid);
$function$;

do $ficha$
declare anterior text; nueva text; patron constant text:='private.cartera_f5_personas_visibles()';
begin
  anterior:=pg_get_functiondef('crm.inversionista_ficha_fn(uuid,integer,integer)'::regprocedure);
  if (length(anterior)-length(replace(anterior,patron,'')))/length(patron) <> 2 then
    raise exception 'La ficha debe conservar dos comprobaciones de visibilidad';
  end if;
  nueva:=replace(anterior,patron,'private.cartera_f5_personas_visibles(v_id)');
  execute nueva;
  if exists (
    select 1 from pg_proc p,
      lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
    where p.oid='private.cartera_f5_personas_visibles(uuid)'::regprocedure
      and a.grantee<>p.proowner
  ) then
    raise exception 'La variante individual debe permanecer privada al propietario';
  end if;
end;
$ficha$;

do $poscondiciones$
declare esperada record; funcion pg_proc%rowtype; cantidad integer; acl_valida boolean;
begin
  for esperada in select * from (values
    ('private.cartera_f5_personas_visibles()','0d7aee4cf344e3e81e6f77f060075d5e',1),
    ('private.cartera_f5_personas_visibles(uuid)','f99c0aaec6e676061c1c53940729b822',1),
    ('crm.inversionista_ficha_fn(uuid,integer,integer)','d0c6543bc7226e027fb8364f137fd02a',2)
  ) x(firma,huella,grants_esperados) loop
    select * into strict funcion from pg_proc where oid=esperada.firma::regprocedure;
    if md5(pg_get_functiondef(funcion.oid)) is distinct from esperada.huella
      or funcion.proowner is distinct from 'postgres'::regrole::oid
      or funcion.prosecdef is not true
      or funcion.proconfig is distinct from array['search_path=""'] then
      raise exception 'Definición o configuración final no ensayada: %',esperada.firma;
    end if;
    select count(*),bool_and(a.privilege_type='EXECUTE' and not a.is_grantable
      and a.grantor=funcion.proowner and (a.grantee=funcion.proowner
        or (esperada.grants_esperados=2 and a.grantee='authenticated'::regrole::oid)))
    into cantidad,acl_valida
    from aclexplode(coalesce(funcion.proacl,acldefault('f',funcion.proowner))) a;
    if cantidad<>esperada.grants_esperados or acl_valida is not true then
      raise exception 'ACL final no ensayada: %',esperada.firma;
    end if;
  end loop;
end;
$poscondiciones$;
commit;
