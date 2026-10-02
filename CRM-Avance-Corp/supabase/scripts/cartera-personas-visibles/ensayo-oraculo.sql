-- ENSAYO DESHECHO en producción: oráculo de igualdad antes/después del cambio en personas_visibles. Termina SIEMPRE en raise.
do $do$
declare
  v_md5 text; v_ger uuid; v_sup uuid; v_vs uuid[]; actores uuid[]; nombres text[];
  res jsonb[]:=array['{}'::jsonb,'{}'::jsonb]; dur jsonb[]:=array['{}'::jsonb,'{}'::jsonb];
  fase int; a int; c int; v jsonb; k text; t0 timestamptz; ids uuid[]; pids uuid[]; n int; h text;
  iguales int:=0; distintos text[]:='{}';
begin
  set local statement_timeout='170s';
  set local lock_timeout='5s';
  select md5(pg_get_functiondef('private.cartera_f5_personas_visibles(uuid)'::regprocedure)) into v_md5;
  if v_md5<>'45b18a6af966f0ddfd137aec0b9b653d' then raise exception 'PREFLIGHT: cuerpo vivo distinto (%)', v_md5; end if;
  select e.perfil_id into v_ger from crm.equipo e where e.rol_crm='gerencia' and e.activo order by e.perfil_id limit 1;
  select l.asignado_supervisor_id into v_sup from crm.leads l join crm.equipo e on e.perfil_id=l.asignado_supervisor_id and e.rol_crm='supervisor' and e.activo
    where l.activo and l.vendedor_id is null group by 1 order by count(*) desc limit 1;
  select array_agg(r) into v_vs from (select i.responsable_relacion_id r from crm.inversionistas i join crm.equipo e on e.perfil_id=i.responsable_relacion_id and e.rol_crm='vendedor' and e.activo
    group by 1 order by count(*) desc limit 2) x;
  actores:=array[v_ger,v_sup,v_vs[1],v_vs[2]]; nombres:=array['gerencia','supervisor','vendedor1','vendedor2'];
  for fase in 1..2 loop
    if fase=2 then
      execute $def$CREATE OR REPLACE FUNCTION private.cartera_f5_personas_visibles(p_inversionista uuid)
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
  ), contactos as materialized (
      select distinct on (x.canonica) x.canonica,d0.*
      from crm.inversionista_datos_contacto d0 join identidades x on x.id=d0.inversionista_id
      order by x.canonica,d0.actualizado_en desc,d0.inversionista_id
    ), todas_fuentes as materialized (
    select * from private.cartera_f5_fuentes()
  ), fuentes as materialized (
    select * from todas_fuentes where es_demo is not true
  ), cierres_nombre as materialized (
    -- Un solo recorrido (29/09/2026): el lateral por persona recorría la CTE fuentes
    -- 22.897 veces (2,3 s de los 2,4 s del listado). Mismo criterio que antes: el
    -- cierre externo más reciente (creado_en desc, id) entre las fuentes no demo
    -- de la persona con empresa distinta de 'avance'.
    select distinct on (f.inversionista_id) f.inversionista_id,ce0.nombre_completo
    from fuentes f join crm.cierres_externos ce0 on ce0.id=f.fuente_id
    where f.empresa<>'avance'
    order by f.inversionista_id,ce0.creado_en desc,ce0.id
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
    coalesce(nullif(btrim(p.nombre_completo),''),case when not i.lector then nullif(btrim(datos.nombre_completo),'') end,nullif(btrim(l.nombre_completo),''),
      nullif(btrim(ce.nombre_completo),''),'Identidad pendiente de completar'),
    case when i.lector then p.tipo_documento else d.tipo_documento end,
    case when i.lector then p.dni else d.documento_normalizado end,
    coalesce(d.verificado and (not i.lector or (d.tipo_documento=p.tipo_documento
      and d.documento_normalizado=p.dni)),false),
    coalesce(p.telefono,case when not i.lector then case when p.id is null and datos.inversionista_id is not null then datos.telefono else l.telefono end end),
    coalesce(p.correo,case when not i.lector then l.correo end),
    i.estado,i.no_contactar or coalesce(l.no_contactar,false),
    i.responsable_relacion_id,r.nombre_completo,i.perfil_id,
    coalesce(pe.perfiles,'{}'::uuid[]),coalesce(le.leads,'{}'::uuid[]),i.creado_en
  from autorizadas i left join contactos datos on datos.canonica=i.id and not i.lector
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
  left join cierres_nombre ce on ce.inversionista_id=i.id and not i.lector
  left join lateral (
    select d0.* from crm.inversionista_identificadores d0
    where d0.inversionista_id=i.id and d0.estado='vigente'
    order by d0.verificado desc,
      case d0.tipo_documento when 'DNI' then 1 when 'CE' then 2 else 3 end,d0.id
    limit 1
  ) d on true;
$function$
$def$;
      select md5(pg_get_functiondef('private.cartera_f5_personas_visibles(uuid)'::regprocedure)) into v_md5;
    end if;
    for a in 1..4 loop
      perform set_config('request.jwt.claim.sub', actores[a]::text, true);
      perform set_config('request.jwt.claims', json_build_object('sub', actores[a], 'role', 'authenticated')::text, true);
      perform set_config('request.jwt.claim.role', 'authenticated', true);
      t0:=clock_timestamp();
      select md5(coalesce(string_agg(p::text,'|' order by p.inversionista_id),'')), count(*), array_agg(p.inversionista_id order by p.inversionista_id)
        into h, n, ids from private.cartera_f5_personas_visibles() p;
      pids:=null;
      select p.perfil_ids into pids from private.cartera_f5_personas_visibles() p where cardinality(p.perfil_ids)>0 order by p.inversionista_id limit 1;
      res[fase]:=res[fase]||jsonb_build_object(nombres[a]||':pv', h||' n='||n);
      dur[fase]:=dur[fase]||jsonb_build_object(nombres[a]||':pv', round(extract(epoch from clock_timestamp()-t0)*1000));
      for c in 1..(case when a=1 then 11 else 3 end) loop
        k:=nombres[a]||':'||(array['l_p1','l_p2','l_p3','l_texto','l_emp','l_estado','l_pv','l_sinresp','l_contacto','l_mes','l_tam10'])[c];
        t0:=clock_timestamp();
        begin
          v:=case c when 1 then crm.cartera_inversionistas_filtrada_fn() when 2 then crm.cartera_inversionistas_filtrada_fn(p_pagina=>2)
            when 3 then crm.cartera_inversionistas_filtrada_fn(p_pagina=>3) when 4 then crm.cartera_inversionistas_filtrada_fn(p_texto=>'a')
            when 5 then crm.cartera_inversionistas_filtrada_fn(p_empresa=>'avance') when 6 then crm.cartera_inversionistas_filtrada_fn(p_estado=>'vigente')
            when 7 then crm.cartera_inversionistas_filtrada_fn(p_por_vencer=>true) when 8 then crm.cartera_inversionistas_filtrada_fn(p_sin_responsable=>true)
            when 9 then crm.cartera_inversionistas_filtrada_fn(p_contacto=>'no_contactar') when 10 then crm.cartera_inversionistas_filtrada_fn(p_mes=>'sin_fecha')
            else crm.cartera_inversionistas_filtrada_fn(p_tamano=>10) end;
        exception when others then v:=to_jsonb('ERROR '||sqlstate||' '||sqlerrm); end;
        res[fase]:=res[fase]||jsonb_build_object(k, md5(v::text)||' total='||coalesce(v->>'total','?'));
        dur[fase]:=dur[fase]||jsonb_build_object(k, round(extract(epoch from clock_timestamp()-t0)*1000));
      end loop;
      begin v:=crm.cartera_inversionistas_estado_fn(); exception when others then v:=to_jsonb('ERROR '||sqlerrm); end;
      res[fase]:=res[fase]||jsonb_build_object(nombres[a]||':estado', md5(v::text));
      for c in 1..(case when a=1 then 3 else 1 end) loop
        exit when ids is null or c>cardinality(ids);
        t0:=clock_timestamp();
        begin v:=crm.inversionista_ficha_fn(ids[c]); exception when others then v:=to_jsonb('ERROR '||sqlstate||' '||sqlerrm); end;
        res[fase]:=res[fase]||jsonb_build_object(nombres[a]||':ficha'||c, md5(v::text));
        dur[fase]:=dur[fase]||jsonb_build_object(nombres[a]||':ficha'||c, round(extract(epoch from clock_timestamp()-t0)*1000));
      end loop;
      if ids is not null and cardinality(ids)>0 then
        begin v:=crm.inversionista_gestion_fn(ids[1]); exception when others then v:=to_jsonb('ERROR '||sqlstate||' '||sqlerrm); end;
        res[fase]:=res[fase]||jsonb_build_object(nombres[a]||':gestion1', md5(v::text));
      end if;
      if pids is not null and cardinality(pids)>0 then
        begin v:=crm.postventa_perfil_fn(pids[1]); exception when others then v:=to_jsonb('ERROR '||sqlstate||' '||sqlerrm); end;
        res[fase]:=res[fase]||jsonb_build_object(nombres[a]||':pv_perfil', md5(v::text));
      end if;
      begin v:=crm.postventa_vencimientos_fn(1,null); exception when others then v:=to_jsonb('ERROR '||sqlstate||' '||sqlerrm); end;
      res[fase]:=res[fase]||jsonb_build_object(nombres[a]||':pv_venc', md5(v::text));
    end loop;
  end loop;
  for k in select jsonb_object_keys(res[1]) loop
    if res[1]->>k = res[2]->>k then iguales:=iguales+1; else distintos:=distintos||(k||' antes='||(res[1]->>k)||' despues='||coalesce(res[2]->>k,'(sin valor)')); end if;
  end loop;
  raise exception E'ENSAYO DESHECHO (rollback)\nmd5 nueva def: %\ncasos iguales: % · distintos: %\n%\nDURACIONES antes: %\nDURACIONES despues: %\nACTORES: %',
    v_md5, iguales, cardinality(distintos), array_to_string(distintos,E'\n'), dur[1]::text, dur[2]::text, res[1]->>'gerencia:pv';
end $do$;
