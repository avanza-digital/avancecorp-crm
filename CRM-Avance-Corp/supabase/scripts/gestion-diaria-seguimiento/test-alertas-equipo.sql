-- En el mismo BEGIN/ROLLBACK de ensayar.mjs. Activa solo SLA sintético de esta
-- transacción, nunca los cortes productivos ni otro banco.
select set_config('request.jwt.claim.sub',gerente::text,true) from f44_actores;
do $$ begin
  if not exists(select 1 from private.sla_politica_operativa(statement_timestamp())) then
    perform crm.publicar_reglas_sla_aprobadas_v2((select max(version) from crm.sla_politicas));
  end if;
  if (select modo from crm.sla_operacion_control where id)<>'activo' then
    perform crm.cambiar_modo_sla_operacion((select revision from crm.sla_operacion_control where id),'activo');
  end if;
end $$;

select set_config('request.jwt.claim.sub',supervisor::text,true) from f44_actores;
set local role authenticated;
do $$ declare r jsonb; sla jsonb; grupo jsonb; begin
  r := crm.gestion_diaria_avisos_fn();
  sla := crm.avisos_sla_resumen_v2_fn();
  perform pg_temp.afirmar(r#>>'{diarias,modo_sla}'='activo','SLA real activo en el ensayo');
  perform pg_temp.afirmar((sla->>'total_avisos')::integer>0,'La prueba SLA debe tener pendientes, no aceptar paridad vacía');
  for grupo in select * from jsonb_array_elements(sla->'grupos') loop
    perform pg_temp.afirmar(exists(select 1 from jsonb_array_elements(r#>'{diarias,alertas}') a
      where a->>'tipo'=grupo->>'bucket' and a->>'total'=grupo->>'total'),'Paridad con grupo SLA '||(grupo->>'bucket'));
  end loop;
  perform pg_temp.afirmar((select count(*) from jsonb_array_elements(r#>'{diarias,alertas}') a
    where a->>'tipo'<>'parado_2h')=jsonb_array_length(sla->'grupos'),'No añade otro grupo SLA');
  perform pg_temp.afirmar(not exists(select 1 from jsonb_array_elements(r#>'{diarias,alertas}') a
    where a->>'id'<>'grupo:'||(a->>'tipo')||':'||auth.uid()
      or jsonb_array_length(a->'miembros')<>(a->>'total')::integer),'Identidad propia y miembros completos');
  perform pg_temp.error_esperado('select private.gestion_diaria_alertas_sla()','42501');
  perform pg_temp.error_esperado('select private.gestion_diaria_contexto(array[]::uuid[],now(),''[]'')','42501');
end $$;
reset role;

-- Compara ids (no solo cantidades) con la fuente autorizada; ningún grupo
-- cruza el subárbol. Los hechos de llamadas conservan RLS del rol puente.
do $$ declare actor uuid; r jsonb; fuente jsonb; begin
  for actor in select supervisor from f44_actores union select supervisor_ajeno from f44_actores loop
    perform set_config('request.jwt.claim.sub',actor::text,true);
    r := private.gestion_diaria_avisos_con_contexto(clock_timestamp());
    fuente := private.sla_operacion_autorizada(null,true);
    perform pg_temp.afirmar(not exists(
      select 1 from jsonb_array_elements(r#>'{diarias,alertas}') a,
        jsonb_array_elements_text(a->'miembros') id
      where a->>'tipo'<>'parado_2h' and not exists(
        select 1 from jsonb_array_elements(fuente->'filas') f,
          jsonb_array_elements(f#>'{estado,avisos}') aviso
        where f#>>'{lead,id}'=id and aviso->>'bucket'=a->>'tipo')),'Cada id y problema pertenece al núcleo autorizado');
    perform pg_temp.afirmar(not exists(select 1 from jsonb_array_elements(r#>'{contexto,equipo}') e
      where (e->>'analista_id')::uuid not in (select private.vendedor_ids_visibles(actor))), 'Contexto propio');
  end loop;
end $$;

-- Antes del corte, >2h (no >=2h); después agrupa en el corte; sábado/domingo.
select set_config('request.jwt.claim.sub',supervisor::text,true) from f44_actores;
do $$ declare a record; caso record; r jsonb; begin
  select * into a from f44_actores;
  for caso in select * from (values
    (0,time '00:00',false,false),(0,time '09:00',true,false),
    (0,time '11:00',true,false),(0,time '11:00:01',true,true),
    (0,time '11:30',true,false),(0,time '18:00',false,false),
    (5,time '11:00:01',true,true),(5,time '13:00',false,false),(6,time '12:00',false,false)
  ) t(dia,hora,en_jornada,inactivo_propio) loop
    r := private.gestion_diaria_avisos_con_contexto(((a.lunes+caso.dia)+caso.hora) at time zone 'America/Lima');
    perform pg_temp.afirmar((r#>>'{contexto,en_jornada}')::boolean=caso.en_jornada,'Contexto de horario '||caso.hora);
    perform pg_temp.afirmar(exists(select 1 from jsonb_array_elements(r#>'{diarias,alertas}') g,
      jsonb_array_elements_text(g->'miembros') id where g->>'tipo'='parado_2h' and id=a.vendedor::text)
      =caso.inactivo_propio,'Inactividad sin duplicar corte '||caso.dia||' '||caso.hora);
    perform pg_temp.afirmar(not exists(select 1 from jsonb_array_elements(r#>'{diarias,alertas}') g,
      jsonb_array_elements_text(g->'miembros') id,jsonb_array_elements(r->'alertas') c,
      jsonb_array_elements(c->'miembros') m where g->>'tipo'='parado_2h' and id=m->>'analista_id'),'No duplica persona/corte');
  end loop;
end $$;
select 'PASS: grupos SLA con datos, ids/ámbitos, privados denegados, contexto horario e inactividad sin duplicar cortes';
