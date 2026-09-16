-- Reversa de la RPC publicada; ejecutar solo tras retirar el frontend v2.
CREATE OR REPLACE FUNCTION crm.cartera_inversionistas_fn(p_pagina integer DEFAULT 1, p_tamano integer DEFAULT 25, p_texto text DEFAULT ''::text, p_empresa text DEFAULT NULL::text, p_responsable uuid DEFAULT NULL::uuid, p_sin_responsable boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_resultado jsonb; v_texto text:=lower(btrim(coalesce(p_texto,'')));
  v_lector boolean:=private.es_lector_global();
begin
  perform private.cartera_f5_exigir();
  if p_pagina is null or p_pagina<1 or p_pagina>1000000
    or p_tamano is null or p_tamano not in (10,25,50)
    or length(v_texto)>120 or v_texto~'[[:cntrl:]]'
    or (p_empresa is not null and p_empresa not in ('avance','qorilazo','prodelco'))
    or p_sin_responsable is null or (p_sin_responsable and p_responsable is not null) then
    raise exception 'Filtros de cartera inválidos' using errcode='22023';
  end if;
  with personas as materialized (select * from private.cartera_f5_personas_visibles()),
  fuentes as materialized (
    select f.* from private.cartera_f5_fuentes_reales() f
    join personas p on p.inversionista_id=f.inversionista_id
    where not v_lector or f.empresa='avance'
  ), filtradas as materialized (
    select p.* from personas p
    where (p_responsable is null or p.responsable_id=p_responsable)
      and (not p_sin_responsable or p.responsable_id is null)
      and (p_empresa is null or exists(select 1 from fuentes f where f.inversionista_id=p.inversionista_id and f.empresa=p_empresa))
      -- strpos interpreta % y _ literalmente: no son comodines de enumeración.
      and (v_texto='' or strpos(lower(concat_ws(' ',p.nombre,p.documento,p.telefono,p.correo)),v_texto)>0
        or exists(select 1 from fuentes f where f.inversionista_id=p.inversionista_id and strpos(f.empresa,v_texto)>0))
  ), pagina as materialized (
    select * from filtradas order by lower(nombre),inversionista_id
    limit p_tamano offset (p_pagina-1)*p_tamano
  ), totales as (
    select f.empresa,f.moneda,count(*) cantidad,
      sum(f.capital) filter(where not f.es_demo) capital_registrado,
      sum(f.capital) filter(where not f.es_demo and f.empresa='avance' and f.estado='activo'
        and exists(select 1 from public.perfiles pf where pf.id=f.perfil_id and pf.activo)) capital_activo
    from fuentes f join filtradas p using(inversionista_id)
    where p_empresa is null or f.empresa=p_empresa group by f.empresa,f.moneda
  )
  select jsonb_build_object('version',1,'pagina',p_pagina,'tamano',p_tamano,
    'total',(select count(*) from filtradas),
    'filas',coalesce((select jsonb_agg(
      (to_jsonb(p)-'perfil_ids'-'lead_ids'-'perfil_id')||jsonb_build_object('empresas',
        coalesce((select jsonb_agg(x.empresa order by x.empresa) from (
          select distinct f.empresa from fuentes f where f.inversionista_id=p.inversionista_id) x),'[]'))
      order by lower(p.nombre),p.inversionista_id) from pagina p),'[]'),
    'totales',coalesce((select jsonb_agg(jsonb_build_object('empresa',t.empresa,'moneda',t.moneda,
      'cantidad',t.cantidad,'capital_registrado',coalesce(t.capital_registrado,0),
      'capital_activo',case when t.empresa='avance' then coalesce(t.capital_activo,0) end)
      order by t.empresa,t.moneda) from totales t),'[]')) into v_resultado;
  perform private.cartera_f5_registrar('lista');
  return v_resultado;
end;
$function$;
drop function crm.cartera_inversionistas_filtrada_fn(integer,integer,text,text,uuid,boolean,text,text,text,text,boolean);
drop function private.cartera_f5_listar(integer,integer,text,text,uuid,boolean,text,text,text,text,boolean,boolean);
notify pgrst,'reload schema';
