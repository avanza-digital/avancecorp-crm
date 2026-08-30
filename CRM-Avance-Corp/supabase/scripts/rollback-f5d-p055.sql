-- MARCHA ATRAS de P-055 F5.d (cerrar las gemelas muertas del catalogo versionado).
-- Devuelve el EXECUTE de authenticated a las 7 funciones cerradas, y NADA mas:
-- el ACL original medido el 30/08 era exactamente {authenticated, postgres}
-- (sin PUBLIC, sin anon, sin service_role), asi que un grant a authenticated
-- restaura el estado al byte. Idempotente: correrlo dos veces deja lo mismo.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';

grant execute on function public.crear_contrato_producto(uuid,jsonb,jsonb)                      to authenticated;
grant execute on function public.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)            to authenticated;
grant execute on function public.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb) to authenticated;
grant execute on function crm.crear_contrato_producto(uuid,jsonb,jsonb)                         to authenticated;
grant execute on function crm.crear_contrato_con_cuenta_producto(uuid,jsonb,jsonb,jsonb)        to authenticated;
grant execute on function crm.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)               to authenticated;
grant execute on function crm.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)    to authenticated;

-- POSTFLIGHT de la marcha atras: el ACL vuelve EXACTAMENTE al medido antes de
-- la F5.d ({authenticated, postgres}) y las de seleccion siguen intactas.
do $$
declare
  v_fns constant text[] := array[
    'public.crear_contrato_producto(uuid,jsonb,jsonb)',
    'public.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)',
    'public.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)',
    'crm.crear_contrato_producto(uuid,jsonb,jsonb)',
    'crm.crear_contrato_con_cuenta_producto(uuid,jsonb,jsonb,jsonb)',
    'crm.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)',
    'crm.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)'
  ];
  v_obj text; v_acl text;
begin
  foreach v_obj in array v_fns loop
    select string_agg(s.quien, ',' order by s.quien)
      into v_acl
      from (select distinct case when a.grantee = 0 then 'PUBLIC' else r.rolname end as quien
              from pg_proc p
              cross join lateral aclexplode(p.proacl) a
              left join pg_roles r on r.oid = a.grantee
             where p.oid = v_obj::regprocedure and a.privilege_type = 'EXECUTE') s;
    if v_acl is distinct from 'authenticated,postgres' then
      raise exception 'rollback F5.d: % no volvio al ACL original (EXECUTE de: %)', v_obj, coalesce(v_acl, 'nadie');
    end if;
    -- El ACL LITERAL entero, no solo los grantees (auditoria Codex, P1):
    -- grantor postgres, sin grant option, y el MISMO orden que el original
    -- medido el 30/08. El ensayo contra prod ya demostro que el ciclo
    -- revoke->grant reproduce este literal al byte.
    if (select p.proacl::text from pg_proc p where p.oid = v_obj::regprocedure)
       is distinct from '{postgres=X/postgres,authenticated=X/postgres}' then
      raise exception 'rollback F5.d: proacl de % no es el literal original (%)', v_obj,
        (select p.proacl::text from pg_proc p where p.oid = v_obj::regprocedure);
    end if;
  end loop;

  if not has_function_privilege('authenticated', 'public.productos_inversion_seleccion_fn(uuid)'::regprocedure, 'EXECUTE')
     or not has_function_privilege('authenticated', 'crm.productos_inversion_seleccion_fn()'::regprocedure, 'EXECUTE') then
    raise exception 'rollback F5.d: una funcion de seleccion del catalogo no esta viva para authenticated';
  end if;

  -- Higiene F1.6: los guardianes corren tambien al deshacer.
  perform private.assert_analista_vigencia();
  perform private.assert_analitica_leads_citas();
end $$;

commit;
