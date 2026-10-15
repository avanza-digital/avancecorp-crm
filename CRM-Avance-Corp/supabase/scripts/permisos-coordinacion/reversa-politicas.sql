begin;
create policy leads_coordinacion_consulta on crm.leads for select to authenticated
  using ((((activo = true) AND ((vendedor_id IN ( SELECT private.vendedor_ids_visibles(( SELECT auth.uid() AS uid)) AS vendedor_ids_visibles)) OR ((vendedor_id IS NULL) AND (asignado_supervisor_id IN ( SELECT private.vendedor_ids_visibles(( SELECT auth.uid() AS uid)) AS vendedor_ids_visibles))) OR (( SELECT private.rol_crm(( SELECT auth.uid() AS uid)) AS rol_crm) = 'gerencia'::text) OR ( SELECT private.es_lector_global() AS es_lector_global)))) or (((activo IS TRUE) AND ( SELECT private.es_coordinacion_consulta() AS es_coordinacion_consulta))));
do $$ declare a text; b text; begin
  select pg_get_expr(polqual,polrelid) into a from pg_policy where polrelid='crm.leads'::regclass and polname='leads_select';
  select pg_get_expr(polqual,polrelid) into b from pg_policy where polrelid='crm.leads'::regclass and polname='leads_coordinacion_consulta';
  if a is distinct from b then raise exception 'Cambió la policy consolidada de leads'; end if;
end; $$;
alter policy leads_select on crm.leads using (((activo = true) AND ((vendedor_id IN ( SELECT private.vendedor_ids_visibles(( SELECT auth.uid() AS uid)) AS vendedor_ids_visibles)) OR ((vendedor_id IS NULL) AND (asignado_supervisor_id IN ( SELECT private.vendedor_ids_visibles(( SELECT auth.uid() AS uid)) AS vendedor_ids_visibles))) OR (( SELECT private.rol_crm(( SELECT auth.uid() AS uid)) AS rol_crm) = 'gerencia'::text) OR ( SELECT private.es_lector_global() AS es_lector_global))));
alter policy leads_coordinacion_consulta on crm.leads using (((activo IS TRUE) AND ( SELECT private.es_coordinacion_consulta() AS es_coordinacion_consulta)));
create policy actividades_coordinacion_consulta on crm.actividades for select to authenticated
  using (((EXISTS ( SELECT 1
   FROM crm.leads l
  WHERE ((l.id = actividades.lead_id) AND (l.activo = true) AND ((l.vendedor_id IN ( SELECT private.vendedor_ids_visibles(( SELECT auth.uid() AS uid)) AS vendedor_ids_visibles)) OR ((l.vendedor_id IS NULL) AND (l.asignado_supervisor_id IN ( SELECT private.vendedor_ids_visibles(( SELECT auth.uid() AS uid)) AS vendedor_ids_visibles))) OR (( SELECT private.rol_crm(( SELECT auth.uid() AS uid)) AS rol_crm) = 'gerencia'::text) OR ( SELECT private.es_lector_global() AS es_lector_global)))))) or ((( SELECT private.es_coordinacion_consulta() AS es_coordinacion_consulta) AND (EXISTS ( SELECT 1
   FROM crm.leads l
  WHERE ((l.id = actividades.lead_id) AND (l.activo IS TRUE)))))));
do $$ declare a text; b text; begin
  select pg_get_expr(polqual,polrelid) into a from pg_policy where polrelid='crm.actividades'::regclass and polname='actividades_select';
  select pg_get_expr(polqual,polrelid) into b from pg_policy where polrelid='crm.actividades'::regclass and polname='actividades_coordinacion_consulta';
  if a is distinct from b then raise exception 'Cambió la policy consolidada de actividades'; end if;
end; $$;
alter policy actividades_select on crm.actividades using ((EXISTS ( SELECT 1
   FROM crm.leads l
  WHERE ((l.id = actividades.lead_id) AND (l.activo = true) AND ((l.vendedor_id IN ( SELECT private.vendedor_ids_visibles(( SELECT auth.uid() AS uid)) AS vendedor_ids_visibles)) OR ((l.vendedor_id IS NULL) AND (l.asignado_supervisor_id IN ( SELECT private.vendedor_ids_visibles(( SELECT auth.uid() AS uid)) AS vendedor_ids_visibles))) OR (( SELECT private.rol_crm(( SELECT auth.uid() AS uid)) AS rol_crm) = 'gerencia'::text) OR ( SELECT private.es_lector_global() AS es_lector_global))))));
alter policy actividades_coordinacion_consulta on crm.actividades using ((( SELECT private.es_coordinacion_consulta() AS es_coordinacion_consulta) AND (EXISTS ( SELECT 1
   FROM crm.leads l
  WHERE ((l.id = actividades.lead_id) AND (l.activo IS TRUE))))));
create policy tareas_coordinacion_consulta on crm.tareas for select to authenticated
  using ((((activo = true) AND ((vendedor_id IN ( SELECT private.vendedor_ids_visibles(( SELECT auth.uid() AS uid)) AS vendedor_ids_visibles)) OR ((vendedor_id IS NULL) AND (asignado_supervisor_id IN ( SELECT private.vendedor_ids_visibles(( SELECT auth.uid() AS uid)) AS vendedor_ids_visibles))) OR (( SELECT private.rol_crm(( SELECT auth.uid() AS uid)) AS rol_crm) = 'gerencia'::text) OR ( SELECT private.es_lector_global() AS es_lector_global)))) or (((activo IS TRUE) AND ( SELECT private.es_coordinacion_consulta() AS es_coordinacion_consulta) AND (EXISTS ( SELECT 1
   FROM crm.leads l
  WHERE ((l.id = tareas.lead_id) AND (l.activo IS TRUE)))))));
do $$ declare a text; b text; begin
  select pg_get_expr(polqual,polrelid) into a from pg_policy where polrelid='crm.tareas'::regclass and polname='tareas_select';
  select pg_get_expr(polqual,polrelid) into b from pg_policy where polrelid='crm.tareas'::regclass and polname='tareas_coordinacion_consulta';
  if a is distinct from b then raise exception 'Cambió la policy consolidada de tareas'; end if;
end; $$;
alter policy tareas_select on crm.tareas using (((activo = true) AND ((vendedor_id IN ( SELECT private.vendedor_ids_visibles(( SELECT auth.uid() AS uid)) AS vendedor_ids_visibles)) OR ((vendedor_id IS NULL) AND (asignado_supervisor_id IN ( SELECT private.vendedor_ids_visibles(( SELECT auth.uid() AS uid)) AS vendedor_ids_visibles))) OR (( SELECT private.rol_crm(( SELECT auth.uid() AS uid)) AS rol_crm) = 'gerencia'::text) OR ( SELECT private.es_lector_global() AS es_lector_global))));
alter policy tareas_coordinacion_consulta on crm.tareas using (((activo IS TRUE) AND ( SELECT private.es_coordinacion_consulta() AS es_coordinacion_consulta) AND (EXISTS ( SELECT 1
   FROM crm.leads l
  WHERE ((l.id = tareas.lead_id) AND (l.activo IS TRUE))))));
notify pgrst,'reload schema';
commit;
