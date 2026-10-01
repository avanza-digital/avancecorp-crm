-- VERIFICACIÓN (solo lectura, termina SIEMPRE en raise) de 20260930213647_crm_potencial_lead.
-- Se corre en producción después de aplicar y registrar. No escribe nada.
do $v$
declare
  v_marcas int; v_eventos int; v_bandera boolean; v_puerta text; v_registro text; v_privadas int; v_tablas int;
begin
  select count(*) into v_marcas from crm.lead_potencial;
  select count(*) into v_eventos from crm.lead_potencial_eventos;
  select f.activo into v_bandera from crm.multiempresa_flags f where f.nombre = 'potencial_lead';
  select string_agg(x.grantee::regrole::text, ',' order by x.grantee::regrole::text) into v_puerta
    from pg_proc p, aclexplode(p.proacl) x
   where p.oid = 'crm.marcar_potencial_lead_fn(uuid,crm.nivel_potencial)'::regprocedure and x.privilege_type = 'EXECUTE';
  select count(*) into v_privadas from pg_proc p, aclexplode(p.proacl) x
   where p.oid in ('private.potencial_rechazo(uuid,uuid)'::regprocedure,
                   'private.potencial_marcar_nucleo(uuid,uuid,crm.nivel_potencial)'::regprocedure,
                   'private.potencial_bloquear_lead(uuid)'::regprocedure,
                   'private.potencial_evento_inmutable()'::regprocedure)
     and x.grantee <> 'postgres'::regrole;
  select count(*) into v_tablas
    from unnest(array['anon','authenticated','service_role']) r(rol),
         unnest(array['crm.lead_potencial','crm.lead_potencial_eventos']) t(tabla),
         unnest(array['SELECT','INSERT','UPDATE','DELETE','TRUNCATE']) x(priv)
   where has_table_privilege(r.rol, t.tabla, x.priv);
  select coalesce(max(name), '(sin registrar)') into v_registro
    from supabase_migrations.schema_migrations where version = '20260930213647';
  raise exception 'VERIFICAR potencial_lead: marcas %, eventos %, bandera % (debe ser false), EXECUTE puerta [%] (debe ser authenticated,postgres), EXECUTE ajeno en privadas % (debe ser 0), permisos API en tablas % (debe ser 0), registro %',
    v_marcas, v_eventos, coalesce(v_bandera::text, '(no existe)'), coalesce(v_puerta, '(ninguno)'), v_privadas, v_tablas, v_registro;
end $v$;
