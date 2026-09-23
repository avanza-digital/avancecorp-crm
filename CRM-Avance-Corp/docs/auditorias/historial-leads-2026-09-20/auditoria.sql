begin transaction isolation level repeatable read read only;
set local statement_timeout = '45000';
do $audit$
declare
  v_actor record;
  v_lead record;
  v_baseline jsonb;
  v_visible jsonb;
  v_ids jsonb;
  v_all_ids jsonb;
  v_pagina jsonb;
  v_last jsonb;
  v_resultados jsonb := '[]'::jsonb;
  v_mismatches integer;
  v_rpc integer;
  v_paginas integer;
  v_leads integer;
  v_acts integer;
  v_denegado boolean;
begin
  select coalesce(jsonb_object_agg(s.id::text,s.ids),'{}'::jsonb)
    into v_baseline
    from (
      select l.id,coalesce(jsonb_agg(a.id::text order by a.creado_en desc,a.id asc) filter (where a.id is not null),'[]'::jsonb) ids
      from crm.leads l left join crm.actividades a on a.lead_id=l.id
      where l.activo group by l.id
    ) s;
  for v_actor in select perfil_id,rol_crm from crm.equipo where activo and rol_crm in ('vendedor','supervisor','gerencia') order by rol_crm,perfil_id loop
    perform set_config('request.jwt.claim.sub',v_actor.perfil_id::text,true);
    perform set_config('request.jwt.claims',jsonb_build_object('sub',v_actor.perfil_id::text,'role','authenticated')::text,true);
    execute 'set local role authenticated';
    select coalesce(jsonb_object_agg(s.id::text,s.ids),'{}'::jsonb) into v_visible
      from (
        select l.id,coalesce(jsonb_agg(a.id::text order by a.creado_en desc,a.id asc) filter(where a.id is not null),'[]'::jsonb) ids
        from crm.leads l left join crm.actividades a on a.lead_id=l.id group by l.id
      ) s;
    select count(*),coalesce(sum(jsonb_array_length(value)),0),count(*) filter(where value is distinct from v_baseline->key)
      into v_leads,v_acts,v_mismatches from jsonb_each(v_visible);
    v_rpc:=0;
    v_paginas:=0;
    for v_lead in select key,value from jsonb_each(v_visible) order by jsonb_array_length(value) desc,key limit 5 loop
      v_pagina:=crm.actividades_de_lead_fn(v_lead.key::uuid,500,null,null);
      select coalesce(jsonb_agg(item->>'id' order by ordinal),'[]'::jsonb) into v_ids
        from jsonb_array_elements(v_pagina->'items') with ordinality x(item,ordinal);
      if v_ids is distinct from v_lead.value then raise exception 'Diferencia RPC completa para rol %',v_actor.rol_crm; end if;
      v_rpc:=v_rpc+1;
      v_all_ids:='[]'::jsonb;
      v_last:=null;
      loop
        v_pagina:=crm.actividades_de_lead_fn(v_lead.key::uuid,7,(v_last->>'creado_en')::timestamptz,(v_last->>'id')::uuid);
        select coalesce(jsonb_agg(item->>'id' order by ordinal),'[]'::jsonb) into v_ids
          from jsonb_array_elements(v_pagina->'items') with ordinality x(item,ordinal);
        v_all_ids:=v_all_ids||v_ids;
        v_paginas:=v_paginas+1;
        exit when jsonb_array_length(v_ids)<7;
        v_last:=(v_pagina->'items')->-1;
      end loop;
      if v_all_ids is distinct from v_lead.value then raise exception 'Diferencia al paginar para rol %',v_actor.rol_crm; end if;
    end loop;
    v_denegado:=false;
    begin
      perform crm.actividades_de_lead_fn('00000000-0000-0000-0000-000000000000'::uuid,100,null,null);
    exception when insufficient_privilege then v_denegado:=true;
    end;
    execute 'reset role';
    v_resultados:=v_resultados||jsonb_build_array(jsonb_build_object('rol',v_actor.rol_crm,'leads_visibles',v_leads,'actividades_visibles',v_acts,'historiales_diferentes',v_mismatches,'rpc_completas_ok',v_rpc,'paginas_cursor_ok',v_paginas,'inexistente_denegado',v_denegado));
  end loop;
  perform set_config('audit.historial_resultado',jsonb_build_object('solo_lectura',true,'leads_activos',(select count(*) from jsonb_each(v_baseline)),'cuentas',v_resultados)::text,true);
end $audit$;
select current_setting('audit.historial_resultado')::jsonb as auditoria;
rollback;
