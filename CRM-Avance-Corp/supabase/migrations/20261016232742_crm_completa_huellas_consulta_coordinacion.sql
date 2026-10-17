-- Completa el mismo ajuste autorizado del control de consulta de Coordinación.
-- Solo sustituye dos constantes antiguas; conserva policies, ACL y restricciones.
begin;
set local lock_timeout='5s';
do $huellas$
declare v_definicion text; v_firma text; v_anterior text; v_nueva text; v_cuerpo text;
begin
  for v_firma,v_cuerpo,v_anterior,v_nueva in select * from (values
    ('private.assert_tareas_pendientes_base()',
     '2082546d71dab7a2082915b59e3fb47c',
     '073deaeb5700bac14209ec795b71567e','1035508f15e5d6c3f6045f620a5611d6'),
    ('private.assert_actividades_recientes_base()',
     '52fb4ccb4f1dd932bd7ad8b68bddacc6',
     'e80e3af900b8d9616c28dcd836f1ac94','f944a324b6e6cab130c8414a049ea265')
  ) as esperadas(firma,cuerpo,anterior,nueva) loop
    select pg_get_functiondef(to_regprocedure(v_firma)) into v_definicion;
    if md5(v_definicion) is distinct from v_cuerpo
      or (length(v_definicion)-length(replace(v_definicion,v_anterior,'')))/32 <> 1 then
      raise exception 'El validador % cambió: revisar antes de sustituir su huella',v_firma;
    end if;
    if (select md5(pg_get_expr(polqual,polrelid)) from pg_policy
        where polrelid=(case when v_firma like '%tareas%' then 'crm.tareas' else 'crm.actividades' end)::regclass
          and polname=case when v_firma like '%tareas%' then 'tareas_select' else 'actividades_select' end)
        is distinct from v_nueva then
      raise exception 'La policy auditada de % cambió',v_firma;
    end if;
    execute replace(v_definicion,v_anterior,v_nueva);
  end loop;
end;
$huellas$;
select private.assert_tareas_pendientes();
select private.assert_actividades_recientes();
select private.assert_actividades_de_lead();
commit;
