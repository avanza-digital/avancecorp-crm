-- MARCHA ATRAS de 20260902040000_crm_lector_global_no_ve_borrados.
--
-- Restaura LAS TRES politicas a su forma anterior AL LITERAL (el texto de
-- abajo es el `qual` normalizado que produccion tenia el 01/09, md5
-- 4fc91b80d5486cb2d7bff5e0abf29eab para leads/tareas y
-- 40b0cd1967e8b20a426407c0975094f9 para actividades). Volver atras significa
-- reabrir el hallazgo: el lector global vuelve a ver lo soft-borrado.
begin;

set local lock_timeout = '5s';

alter policy leads_select on crm.leads using (
  ((activo = true) and ((vendedor_id in ( select private.vendedor_ids_visibles(( select auth.uid() as uid)) as vendedor_ids_visibles)) or ((vendedor_id is null) and (asignado_supervisor_id in ( select private.vendedor_ids_visibles(( select auth.uid() as uid)) as vendedor_ids_visibles))) or (( select private.rol_crm(( select auth.uid() as uid)) as rol_crm) = 'gerencia'::text))) or ( select private.es_lector_global() as es_lector_global)
);

alter policy tareas_select on crm.tareas using (
  ((activo = true) and ((vendedor_id in ( select private.vendedor_ids_visibles(( select auth.uid() as uid)) as vendedor_ids_visibles)) or ((vendedor_id is null) and (asignado_supervisor_id in ( select private.vendedor_ids_visibles(( select auth.uid() as uid)) as vendedor_ids_visibles))) or (( select private.rol_crm(( select auth.uid() as uid)) as rol_crm) = 'gerencia'::text))) or ( select private.es_lector_global() as es_lector_global)
);

alter policy actividades_select on crm.actividades using (
  exists ( select 1
     from crm.leads l
    where ((l.id = actividades.lead_id) and (((l.activo = true) and ((l.vendedor_id in ( select private.vendedor_ids_visibles(( select auth.uid() as uid)) as vendedor_ids_visibles)) or ((l.vendedor_id is null) and (l.asignado_supervisor_id in ( select private.vendedor_ids_visibles(( select auth.uid() as uid)) as vendedor_ids_visibles))) or (( select private.rol_crm(( select auth.uid() as uid)) as rol_crm) = 'gerencia'::text))) or ( select private.es_lector_global() as es_lector_global))))
);

-- Postflight: las tres vuelven a dar la huella ORIGINAL, byte a byte.
do $post$
declare v_fila record; v_md5 text;
begin
  for v_fila in
    select * from (values
      ('leads',       'leads_select',       '4fc91b80d5486cb2d7bff5e0abf29eab'),
      ('tareas',      'tareas_select',      '4fc91b80d5486cb2d7bff5e0abf29eab'),
      ('actividades', 'actividades_select', '40b0cd1967e8b20a426407c0975094f9')
    ) as t(tabla, politica, md5_original)
  loop
    select pg_catalog.md5(p.qual) into v_md5
      from pg_catalog.pg_policies p
     where p.schemaname = 'crm' and p.tablename = v_fila.tabla
       and p.policyname = v_fila.politica and p.cmd = 'SELECT';
    if v_md5 is distinct from v_fila.md5_original then
      raise exception 'ROLLBACK INCOMPLETO: crm.%.% quedo con huella % (original %)',
        v_fila.tabla, v_fila.politica, v_md5, v_fila.md5_original;
    end if;
  end loop;
  raise notice 'ROLLBACK OK: las tres politicas de vuelta a su forma original al byte';
end
$post$;

commit;
