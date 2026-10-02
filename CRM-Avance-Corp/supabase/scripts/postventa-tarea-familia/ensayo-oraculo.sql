-- ENSAYO DESHECHO en producción: oráculo de igualdad antes/después de 20260930000550_crm_postventa_tarea_json_por_familia. Termina SIEMPRE en raise.
-- No puede ser read only (postventa_modo toma FOR SHARE); el raise final lo deshace todo.
do $do$
declare
  v_md5 text; actores uuid[]; nombres text[]; res jsonb[]:=array['{}'::jsonb,'{}'::jsonb]; dur jsonb[]:=array['{}'::jsonb,'{}'::jsonb];
  fase int; a int; v jsonb; t0 timestamptz; h text; n int; iguales int:=0; distintos text[]:='{}'; k text;
begin
  set local statement_timeout='170s';
  set local lock_timeout='5s';
  select md5(pg_get_functiondef('private.postventa_tarea_json(crm.tareas)'::regprocedure)) into v_md5;
  if v_md5<>'c29fd1d25ab775ecd63ab2660a847d0e' then raise exception 'PREFLIGHT: cuerpo vivo distinto (%)', v_md5; end if;
  -- actores: gerencia, el supervisor con bandeja y los 2 responsables con más personas de postventa
  select array_agg(u) into actores from (
    select e.perfil_id u, 0 o from crm.equipo e where e.rol_crm='gerencia' and e.activo order by e.perfil_id limit 1) g;
  actores := actores || (select l.asignado_supervisor_id from crm.leads l join crm.equipo e on e.perfil_id=l.asignado_supervisor_id and e.rol_crm='supervisor' and e.activo
    where l.activo and l.vendedor_id is null group by 1 order by count(*) desc limit 1);
  actores := actores || array(select i.responsable_relacion_id from crm.tareas t join crm.inversionistas i on i.id=t.inversionista_id
    join crm.equipo e on e.perfil_id=i.responsable_relacion_id and e.activo where t.inversionista_id is not null and t.activo and t.estado='pendiente'
    and i.responsable_relacion_id is not null group by 1 order by count(*) desc limit 2);
  nombres := array['gerencia','supervisor','responsable1','responsable2'];
  for fase in 1..2 loop
    if fase=2 then
      execute $def$CREATE OR REPLACE FUNCTION private.postventa_tarea_json(p_t crm.tareas)
 RETURNS jsonb
 LANGUAGE sql
 STABLE STRICT
 SET search_path TO ''
AS $function$
  select jsonb_build_object(
    'id',p_t.id,'lead_id',p_t.lead_id,'perfil_id',p_t.perfil_id,
    'inversionista_id',p_t.inversionista_id,'postventa_revision',p_t.postventa_revision,
    'inversionista_canonico_id',private.inversionista_canonica(p_t.inversionista_id),
    'postventa_perfil_ids',(with recursive familia as (
        -- Candidatas: la raíz canónica de la persona y quienes cuelgan de ella (tope 16, como
        -- inversionista_canonica). Es un superconjunto de las personas con la misma canónica; el
        -- filtro de abajo conserva el criterio EXACTO de antes sin recorrer las 565 personas por
        -- tarea (320 de los 532 ms de la agenda de postventa, medido el 29/09/2026).
        select i.id,1 as n from crm.inversionistas i where i.id=private.inversionista_canonica(p_t.inversionista_id)
        union all
        select i.id,f.n+1 from crm.inversionistas i join familia f on i.inversionista_canonico_id=f.id where f.n<16)
      select array(select i.perfil_id from crm.inversionistas i
        where i.id in (select f.id from familia f) and i.perfil_id is not null
          and private.inversionista_canonica(i.id)=private.inversionista_canonica(p_t.inversionista_id)
        order by i.perfil_id)),
    'vendedor_id',p_t.vendedor_id,'asignado_supervisor_id',p_t.asignado_supervisor_id,
    'tipo',p_t.tipo,'titulo',p_t.titulo,'nota',p_t.nota,'vence_en',p_t.vence_en,
    'duracion_min',p_t.duracion_min,'estado',p_t.estado,'modalidad_reunion',p_t.modalidad_reunion,
    'ubicacion_reunion',p_t.ubicacion_reunion,'enlace_reunion',p_t.enlace_reunion,
    'resultado_reunion',p_t.resultado_reunion,'motivo_no_realizada',p_t.motivo_no_realizada,
    'detalle_cierre_reunion',p_t.detalle_cierre_reunion,'confirmada_en',p_t.confirmada_en,
    'reagendada_de',p_t.reagendada_de,'reprogramaciones',p_t.reprogramaciones,
    'activo',p_t.activo,'creado_en',p_t.creado_en);
$function$$def$;
      select md5(pg_get_functiondef('private.postventa_tarea_json(crm.tareas)'::regprocedure)) into v_md5;
    end if;
    -- todas las tareas con persona, como postgres (la función es INVOKER; postgres ve todo): igualdad fila a fila
    select md5(coalesce(string_agg(private.postventa_tarea_json(t)::text,'|' order by t.id),'')), count(*) into h, n
      from crm.tareas t where t.inversionista_id is not null;
    res[fase]:=res[fase]||jsonb_build_object('todas:tarea_json', h||' n='||n);
    t0:=clock_timestamp(); perform private.postventa_tarea_json(t) from crm.tareas t where t.inversionista_id is not null;
    dur[fase]:=dur[fase]||jsonb_build_object('todas:tarea_json', round(extract(epoch from clock_timestamp()-t0)*1000));
    for a in 1..cardinality(actores) loop
      continue when actores[a] is null;
      perform set_config('request.jwt.claim.sub', actores[a]::text, true);
      perform set_config('request.jwt.claims', json_build_object('sub', actores[a], 'role', 'authenticated')::text, true);
      perform set_config('request.jwt.claim.role', 'authenticated', true);
      t0:=clock_timestamp();
      begin v:=crm.postventa_agenda_fn(); exception when others then v:=to_jsonb('ERROR '||sqlstate||' '||sqlerrm); end;
      dur[fase]:=dur[fase]||jsonb_build_object(nombres[a]||':agenda', round(extract(epoch from clock_timestamp()-t0)*1000));
      res[fase]:=res[fase]||jsonb_build_object(nombres[a]||':agenda', md5(v::text)||' n='||coalesce(jsonb_array_length(case when jsonb_typeof(v)='array' then v end),0));
      begin v:=crm.cola_accion_v3_fn(); exception when others then v:=to_jsonb('ERROR '||sqlstate||' '||left(sqlerrm,60)); end;
      res[fase]:=res[fase]||jsonb_build_object(nombres[a]||':cola_v3', md5(v::text));
      begin v:=crm.tareas_pendientes_fn(); exception when others then v:=to_jsonb('ERROR '||sqlstate||' '||left(sqlerrm,60)); end;
      res[fase]:=res[fase]||jsonb_build_object(nombres[a]||':tareas_pendientes', md5(v::text));
    end loop;
  end loop;
  for k in select jsonb_object_keys(res[1]) loop
    if res[1]->>k = res[2]->>k then iguales:=iguales+1; else distintos:=distintos||(k||' antes='||(res[1]->>k)||' despues='||coalesce(res[2]->>k,'(sin valor)')); end if;
  end loop;
  raise exception E'ENSAYO DESHECHO (rollback)\nmd5 nueva def: %\ncasos iguales: % · distintos: %\n%\nDURACIONES antes: %\nDURACIONES despues: %',
    v_md5, iguales, cardinality(distintos), array_to_string(distintos,E'\n'), dur[1]::text, dur[2]::text;
end $do$;
