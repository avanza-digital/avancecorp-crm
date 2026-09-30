-- ENSAYO DESHECHO en producción: oráculo de igualdad antes/después de 20260930002929_crm_sla_resumen_solo_operativos. Termina SIEMPRE en raise.
do $do$
declare
  v_md5 text; actores uuid[]; nombres text[]:=array['gerencia','supervisor','vendedor1','vendedor2'];
  res jsonb[]:=array['{}'::jsonb,'{}'::jsonb]; dur jsonb[]:=array['{}'::jsonb,'{}'::jsonb];
  fase int; a int; v jsonb; t0 timestamptz; iguales int:=0; distintos text[]:='{}'; k text; g text; ids uuid[];
begin
  set local statement_timeout='170s';
  set local lock_timeout='5s';
  select md5(pg_get_functiondef('crm.avisos_sla_resumen_v2_fn()'::regprocedure)) into v_md5;
  if v_md5<>'7b5f75dfb6ac3e480659bdef3dc5ac0f' then raise exception 'PREFLIGHT: cuerpo vivo distinto (%)', v_md5; end if;
  actores := array[(select e.perfil_id from crm.equipo e where e.rol_crm='gerencia' and e.activo order by e.perfil_id limit 1)];
  actores := actores || (select l.asignado_supervisor_id from crm.leads l join crm.equipo e on e.perfil_id=l.asignado_supervisor_id and e.rol_crm='supervisor' and e.activo where l.activo and l.vendedor_id is null group by 1 order by count(*) desc limit 1);
  actores := actores || array(select l.vendedor_id from crm.leads l join crm.equipo e on e.perfil_id=l.vendedor_id and e.rol_crm='vendedor' and e.activo where l.activo and l.etapa in ('nuevo','contactado','reunion_agendada','propuesta_enviada') group by 1 order by count(*) desc limit 2);
  select array_agg(id) into ids from crm.leads where activo and etapa in ('nuevo','contactado','reunion_agendada','propuesta_enviada');
  for fase in 1..2 loop
    if fase=2 then
      execute $def$CREATE OR REPLACE FUNCTION private.sla_leads_operativos()
 RETURNS uuid[]
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  -- Ids de las oportunidades activas en etapa comercial: las mismas cuatro etapas que
  -- private.sla_operacion_leads considera NO terminales (v_terminal). Sin PII; el núcleo
  -- aplica después su propia visibilidad por actor. Nunca NULL: vacío = '{}'.
  select coalesce(array_agg(l.id order by l.id), '{}'::uuid[])
  from crm.leads l
  where l.activo is true
    and l.etapa in ('nuevo','contactado','reunion_agendada','propuesta_enviada');
$function$$def$;
      execute 'revoke all on function private.sla_leads_operativos() from public, anon, authenticated, service_role';
      execute $def$CREATE OR REPLACE FUNCTION crm.avisos_sla_resumen_v2_fn()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_datos jsonb;v_total integer;v_avisos integer;v_criticas integer;v_grupos jsonb;
begin
  -- Misma ventana autorizada y mismo instante que ficha y cola. El conteo
  -- incluye toda la cartera visible, sin depender del lote local ni pagina.
  -- Solo las oportunidades que pueden avisar: activas y en etapa comercial (las descartadas y
  -- convertidas son «lead_terminal» en el núcleo y nunca producen avisos ni «pendientes»; 1.139 de
  -- 2.583 el 29/09/2026). El núcleo, su autoridad y su reloj no cambian; el ayudante vive en
  -- private porque este adaptador no puede leer hechos crudos (assert_sla_avisos).
  v_datos:=private.sla_operacion_autorizada(private.sla_leads_operativos(),true);
  with filas as materialized (
    select f.value from jsonb_array_elements(v_datos->'filas') f
    where v_datos->>'modo'='activo' and (f.value#>>'{senales,pendientes}')::boolean
  ), avisos as materialized (
    select a.value from filas f cross join lateral jsonb_array_elements(f.value#>'{estado,avisos}') a
  ), grupos as (
    select a.value->>'bucket' as bucket,count(*) as total,
      min((a.value->>'prioridad')::integer) as prioridad
    from avisos a group by a.value->>'bucket'
  )
  select (select count(*) from filas),(select count(*) from avisos),
    (select count(*) from avisos a where a.value->>'severidad'='critica'),
    coalesce((select jsonb_agg(jsonb_build_object('bucket',g.bucket,'total',g.total) order by g.prioridad) from grupos g),'[]'::jsonb)
  into v_total,v_avisos,v_criticas,v_grupos;
  return (v_datos-'filas'-'contexto_ambito')||jsonb_build_object(
    'total_oportunidades',v_total,'total_avisos',v_avisos,'criticas',v_criticas,'grupos',v_grupos);
end;
$function$$def$;
      select md5(pg_get_functiondef('crm.avisos_sla_resumen_v2_fn()'::regprocedure)) into v_md5;
      g := private.assert_sla_avisos();
    end if;
    for a in 1..4 loop
      continue when actores[a] is null;
      perform set_config('request.jwt.claim.sub', actores[a]::text, true);
      perform set_config('request.jwt.claims', json_build_object('sub', actores[a], 'role', 'authenticated')::text, true);
      perform set_config('request.jwt.claim.role', 'authenticated', true);
      t0:=clock_timestamp();
      begin v:=crm.avisos_sla_resumen_v2_fn(); exception when others then v:=to_jsonb('ERROR '||sqlstate||' '||sqlerrm); end;
      dur[fase]:=dur[fase]||jsonb_build_object(nombres[a]||':resumen', round(extract(epoch from clock_timestamp()-t0)*1000));
      res[fase]:=res[fase]||jsonb_build_object(nombres[a]||':resumen', md5((v - 'calculado_en')::text)||' claves='||(select count(*) from jsonb_object_keys(v)));
      -- controles (no deben cambiar): estado de 5 leads operativos y la cola v3
      begin v:=crm.estado_sla_leads_v2_fn(ids[1:5]); exception when others then v:=to_jsonb('ERROR '||sqlstate||' '||left(sqlerrm,60)); end;
      res[fase]:=res[fase]||jsonb_build_object(nombres[a]||':estado_v2', md5((v - 'calculado_en')::text));
      begin v:=crm.cola_accion_v3_fn(); exception when others then v:=to_jsonb('ERROR '||sqlstate||' '||left(sqlerrm,60)); end;
      res[fase]:=res[fase]||jsonb_build_object(nombres[a]||':cola_v3', md5((v - 'calculado_en')::text));
    end loop;
  end loop;
  for k in select jsonb_object_keys(res[1]) loop
    if res[1]->>k = res[2]->>k then iguales:=iguales+1; else distintos:=distintos||(k||' antes='||(res[1]->>k)||' despues='||coalesce(res[2]->>k,'(sin valor)')); end if;
  end loop;
  raise exception E'ENSAYO DESHECHO (rollback)\nmd5 nueva def: %\nguardián: %\ncasos iguales: % · distintos: %\n%\nDURACIONES antes: %\nDURACIONES despues: %',
    v_md5, g, iguales, cardinality(distintos), array_to_string(distintos,E'\n'), dur[1]::text, dur[2]::text;
end $do$;
