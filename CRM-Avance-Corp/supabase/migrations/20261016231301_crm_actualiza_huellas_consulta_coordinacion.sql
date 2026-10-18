-- PROPUESTA PENDIENTE DE APROBACIÓN. No amplía permisos ni cambia policies.
-- Las dos policies vigentes ya admiten la consulta de Coordinación.
-- El validador conserva huellas anteriores a ese cambio y bloquea el gate.
-- Ensayar en rama, ejecutar matriz RLS y advisors antes de llevar a producción.
begin;
set local lock_timeout='5s';
do $guardas$
declare v_definicion text;
begin
  select pg_get_functiondef('private.assert_actividades_de_lead_base()'::regprocedure)
    into v_definicion;
  if md5(v_definicion) is distinct from '4c005154df530ddc390ead069aa2b364'
    or (select md5(pg_get_expr(polqual,polrelid)) from pg_policy
        where polrelid='crm.actividades'::regclass and polname='actividades_select')
       is distinct from 'f944a324b6e6cab130c8414a049ea265'
    or (select md5(pg_get_expr(polqual,polrelid)) from pg_policy
        where polrelid='crm.leads'::regclass and polname='leads_select')
       is distinct from '6b66f5dbb3333ebf6eab5a38bd5b06f6' then
    raise exception 'La auditoría o sus policies cambiaron; revisar antes de actualizar las huellas';
  end if;
  execute replace(replace(v_definicion,
    'e80e3af900b8d9616c28dcd836f1ac94','f944a324b6e6cab130c8414a049ea265'),
    '073deaeb5700bac14209ec795b71567e','6b66f5dbb3333ebf6eab5a38bd5b06f6');
end;
$guardas$;
select private.assert_actividades_de_lead();
select private.assert_gestion_diaria_registro();
commit;
-- Reversa: restaurar únicamente estas dos constantes al valor anterior,
-- conservando owner, ACL, modo de seguridad, firma y todas las validaciones.
