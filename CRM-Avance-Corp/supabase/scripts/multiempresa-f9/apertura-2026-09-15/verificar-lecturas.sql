-- Muestra de lectura por tres roles, priorizando usuarios fuera del piloto.
-- Auditorías de lectura dentro de ROLLBACK; ninguna operación económica.
begin isolation level read committed;
set local search_path='';set local statement_timeout='45s';set local lock_timeout='2s';
do $f9_lecturas$
declare a record;lista jsonb;ficha jsonb;ajena jsonb;visibles uuid[];propia uuid;fuera uuid;
  diferencias integer;cantidad integer;resultado jsonb:='[]';esperadas jsonb;obtenidas jsonb;
begin
  for a in select distinct on(e.rol_crm) e.perfil_id,e.rol_crm,
    exists(select 1 from crm.piloto_f8_miembros m where m.perfil_id=e.perfil_id and m.activo) fue_piloto
    from crm.equipo e join public.perfiles p on p.id=e.perfil_id and p.activo
    where e.activo and e.rol_crm in('vendedor','supervisor','gerencia')
    order by e.rol_crm,fue_piloto,
      (select count(*) from crm.inversionistas i left join crm.equipo responsable on responsable.perfil_id=i.responsable_relacion_id
        where i.responsable_relacion_id=e.perfil_id or responsable.supervisor_id=e.perfil_id) desc,e.perfil_id
  loop
    perform set_config('request.jwt.claim.sub',a.perfil_id::text,true);
    perform set_config('request.jwt.claims',jsonb_build_object('sub',a.perfil_id,'role','authenticated')::text,true);
    select coalesce(array_agg(inversionista_id),'{}') into visibles from private.cartera_f5_personas_visibles();
    select coalesce(jsonb_agg(to_jsonb(t) order by empresa,moneda),'[]') into esperadas from(
      select empresa,moneda,count(*) cantidad,sum(capital) capital_registrado
      from private.cartera_f5_fuentes_reales() where inversionista_id=any(visibles) group by empresa,moneda)t;
    propia:=null;fuera:=null;ficha:=null;ajena:=null;
    if a.rol_crm<>'gerencia' then
      select inversionista_id into fuera from private.cartera_f5_fuentes_reales()
        where not (inversionista_id=any(visibles)) order by fuente_id limit 1;
    end if;
    set local role authenticated;
    lista:=crm.cartera_inversionistas_fn(p_tamano=>10);
    if (lista->>'total')::integer is distinct from cardinality(visibles)
      or exists(select 1 from jsonb_array_elements(lista->'filas') x
        where not ((x->>'inversionista_id')::uuid=any(visibles))) then raise exception 'Lista fuera de ámbito';end if;
    propia:=(lista#>>'{filas,0,inversionista_id}')::uuid;
    if propia is not null then ficha:=crm.inversionista_ficha_fn(propia,1,1);end if;
    if fuera is not null then ajena:=crm.inversionista_ficha_fn(fuera,1,1);end if;
    reset role;
    if ajena is not null then raise exception 'Ficha ajena visible';end if;
    select coalesce(jsonb_agg(jsonb_build_object('empresa',x->>'empresa','moneda',x->>'moneda',
      'cantidad',(x->>'cantidad')::bigint,'capital_registrado',(x->>'capital_registrado')::numeric)
      order by x->>'empresa',x->>'moneda'),'[]') into obtenidas from jsonb_array_elements(lista->'totales') x;
    if obtenidas is distinct from esperadas then raise exception 'Totales de cartera distintos del núcleo';end if;
    if propia is not null then
      select count(*) into cantidad from private.cartera_f5_fuentes_reales() where inversionista_id=propia;
      if ficha is null or (ficha->>'inversiones_total')::integer is distinct from cantidad then
        raise exception 'Ficha propia incompleta';end if;
      select count(*) into diferencias from jsonb_to_recordset(ficha->'inversiones')
        x(fuente_id uuid,empresa text,moneda text,capital numeric)
        left join private.cartera_f5_fuentes_reales() f on f.fuente_id=x.fuente_id and f.empresa=x.empresa
        where f.fuente_id is null or f.inversionista_id is distinct from propia
          or f.moneda is distinct from x.moneda or f.capital is distinct from x.capital;
      if diferencias<>0 then raise exception 'Fuente de ficha distinta del núcleo';end if;
    end if;
    resultado:=resultado||jsonb_build_array(jsonb_build_object('actor',md5('F9-20260915:'||a.perfil_id::text),
      'rol',a.rol_crm,'fue_piloto',a.fue_piloto,'personas_visibles',cardinality(visibles),
      'filas_muestra',jsonb_array_length(lista->'filas'),'totales_coinciden',true,
      'ficha_propia_comprobada',propia is not null,'ficha_ajena_denegada',fuera is not null and ajena is null));
  end loop;
  if jsonb_array_length(resultado)<>3 then raise exception 'Faltan roles en la muestra';end if;
  perform set_config('f9.lecturas',resultado::text,true);
end $f9_lecturas$;
select jsonb_build_object('estado','PASS','corte',clock_timestamp(),'roles',current_setting('f9.lecturas')::jsonb) evidencia;
rollback;
