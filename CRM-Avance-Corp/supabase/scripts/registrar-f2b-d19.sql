-- ============================================================================
-- REGISTRO de F2.b [D-19] (20260906200000) en supabase_migrations.schema_migrations.
-- Idempotente: se puede correr dos veces. Se niega si lo aplicado no es lo que dice el archivo.
-- md5 del archivo de migración: 0efa2304d0402a1cd7f47bb3eb757760
-- ============================================================================
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f2b_d19_bandera_bajo_candado'));
do $chk$
begin
  if to_regprocedure('private.resolver_en_puertas_bajo_candado()') is null then
    raise exception 'REGISTRO D-19: no está private.resolver_en_puertas_bajo_candado(): ¿aplicaste la migración?';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'crm.actualizar_cliente_gerencia(uuid, jsonb)'::regprocedure
                  and md5(p.prosrc) = '96ca3748c4b455e1dd6207b927684006'
                  and p.prosecdef = true and p.proowner = 'postgres'::regrole
                  and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path=""'
                  and coalesce((select string_agg(a.grantee::regrole::text||':'||a.privilege_type, ',' order by a.grantee::regrole::text||a.privilege_type) from aclexplode(p.proacl) a), 'null') = 'postgres:EXECUTE') then
    raise exception 'POSTFLIGHT D-19: crm.actualizar_cliente_gerencia(uuid, jsonb) no quedó como se esperaba (cuerpo, definer, dueño, config o permisos)';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'crm.alta_cliente_identidad_fn(text, jsonb)'::regprocedure
                  and md5(p.prosrc) = 'a567140f4b30079eb1167aae554218b4'
                  and p.prosecdef = true and p.proowner = 'postgres'::regrole
                  and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path="",lock_timeout=5s'
                  and coalesce((select string_agg(a.grantee::regrole::text||':'||a.privilege_type, ',' order by a.grantee::regrole::text||a.privilege_type) from aclexplode(p.proacl) a), 'null') = 'authenticated:EXECUTE,postgres:EXECUTE,service_role:EXECUTE') then
    raise exception 'POSTFLIGHT D-19: crm.alta_cliente_identidad_fn(text, jsonb) no quedó como se esperaba (cuerpo, definer, dueño, config o permisos)';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'crm.convertir_lead(uuid, uuid)'::regprocedure
                  and md5(p.prosrc) = '4e0b2252ebe16cd98c490638d64a3d23'
                  and p.prosecdef = true and p.proowner = 'postgres'::regrole
                  and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path="",lock_timeout=5s'
                  and coalesce((select string_agg(a.grantee::regrole::text||':'||a.privilege_type, ',' order by a.grantee::regrole::text||a.privilege_type) from aclexplode(p.proacl) a), 'null') = 'authenticated:EXECUTE,postgres:EXECUTE') then
    raise exception 'POSTFLIGHT D-19: crm.convertir_lead(uuid, uuid) no quedó como se esperaba (cuerpo, definer, dueño, config o permisos)';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'crm.corregir_documento_inversionista_fn(uuid, text, text, text, uuid)'::regprocedure
                  and md5(p.prosrc) = '7067b835fc8ed45f6c5e7261708f0c28'
                  and p.prosecdef = true and p.proowner = 'postgres'::regrole
                  and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path="",lock_timeout=5s'
                  and coalesce((select string_agg(a.grantee::regrole::text||':'||a.privilege_type, ',' order by a.grantee::regrole::text||a.privilege_type) from aclexplode(p.proacl) a), 'null') = 'authenticated:EXECUTE,postgres:EXECUTE') then
    raise exception 'POSTFLIGHT D-19: crm.corregir_documento_inversionista_fn(uuid, text, text, text, uuid) no quedó como se esperaba (cuerpo, definer, dueño, config o permisos)';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'crm.crear_contrato_con_cuenta(jsonb, jsonb, jsonb)'::regprocedure
                  and md5(p.prosrc) = '0de7a130ae366cde54035e2c50f213e2'
                  and p.prosecdef = true and p.proowner = 'postgres'::regrole
                  and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path=""'
                  and coalesce((select string_agg(a.grantee::regrole::text||':'||a.privilege_type, ',' order by a.grantee::regrole::text||a.privilege_type) from aclexplode(p.proacl) a), 'null') = 'postgres:EXECUTE') then
    raise exception 'POSTFLIGHT D-19: crm.crear_contrato_con_cuenta(jsonb, jsonb, jsonb) no quedó como se esperaba (cuerpo, definer, dueño, config o permisos)';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'crm.eliminar_cliente_fn(uuid)'::regprocedure
                  and md5(p.prosrc) = '7be05d4584ed15dbd47fc849e51c8f9c'
                  and p.prosecdef = true and p.proowner = 'postgres'::regrole
                  and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path="",lock_timeout=5s'
                  and coalesce((select string_agg(a.grantee::regrole::text||':'||a.privilege_type, ',' order by a.grantee::regrole::text||a.privilege_type) from aclexplode(p.proacl) a), 'null') = 'postgres:EXECUTE,service_role:EXECUTE') then
    raise exception 'POSTFLIGHT D-19: crm.eliminar_cliente_fn(uuid) no quedó como se esperaba (cuerpo, definer, dueño, config o permisos)';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'crm.enlazar_lead_inversionista_fn(uuid, uuid, text)'::regprocedure
                  and md5(p.prosrc) = 'ae7a1c05cbf1659c2ef39783fb0d034d'
                  and p.prosecdef = true and p.proowner = 'postgres'::regrole
                  and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path="",lock_timeout=5s'
                  and coalesce((select string_agg(a.grantee::regrole::text||':'||a.privilege_type, ',' order by a.grantee::regrole::text||a.privilege_type) from aclexplode(p.proacl) a), 'null') = 'authenticated:EXECUTE,postgres:EXECUTE') then
    raise exception 'POSTFLIGHT D-19: crm.enlazar_lead_inversionista_fn(uuid, uuid, text) no quedó como se esperaba (cuerpo, definer, dueño, config o permisos)';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'crm.fijar_membresia_activa_fn(uuid, boolean, uuid, timestamp with time zone, uuid)'::regprocedure
                  and md5(p.prosrc) = '4f6829b5f07a96d431cea16136e0daa4'
                  and p.prosecdef = true and p.proowner = 'postgres'::regrole
                  and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path=""'
                  and coalesce((select string_agg(a.grantee::regrole::text||':'||a.privilege_type, ',' order by a.grantee::regrole::text||a.privilege_type) from aclexplode(p.proacl) a), 'null') = 'authenticated:EXECUTE,postgres:EXECUTE') then
    raise exception 'POSTFLIGHT D-19: crm.fijar_membresia_activa_fn(uuid, boolean, uuid, timestamp with time zone, uuid) no quedó como se esperaba (cuerpo, definer, dueño, config o permisos)';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'crm.fusionar_inversionistas_fn(uuid, uuid, text, text)'::regprocedure
                  and md5(p.prosrc) = '04de1797b11de93502ecb63487565bf6'
                  and p.prosecdef = true and p.proowner = 'postgres'::regrole
                  and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path="",lock_timeout=5s'
                  and coalesce((select string_agg(a.grantee::regrole::text||':'||a.privilege_type, ',' order by a.grantee::regrole::text||a.privilege_type) from aclexplode(p.proacl) a), 'null') = 'authenticated:EXECUTE,postgres:EXECUTE') then
    raise exception 'POSTFLIGHT D-19: crm.fusionar_inversionistas_fn(uuid, uuid, text, text) no quedó como se esperaba (cuerpo, definer, dueño, config o permisos)';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'crm.reasignar_responsable_relacion_fn(uuid, uuid, text)'::regprocedure
                  and md5(p.prosrc) = 'db063e46ca67e7c651c630625411870f'
                  and p.prosecdef = true and p.proowner = 'postgres'::regrole
                  and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path="",lock_timeout=5s'
                  and coalesce((select string_agg(a.grantee::regrole::text||':'||a.privilege_type, ',' order by a.grantee::regrole::text||a.privilege_type) from aclexplode(p.proacl) a), 'null') = 'authenticated:EXECUTE,postgres:EXECUTE') then
    raise exception 'POSTFLIGHT D-19: crm.reasignar_responsable_relacion_fn(uuid, uuid, text) no quedó como se esperaba (cuerpo, definer, dueño, config o permisos)';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'crm.registrar_reingreso_lead_fn(uuid, text, jsonb)'::regprocedure
                  and md5(p.prosrc) = '2875987459d47958333637736c057ffb'
                  and p.prosecdef = true and p.proowner = 'postgres'::regrole
                  and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path=""'
                  and coalesce((select string_agg(a.grantee::regrole::text||':'||a.privilege_type, ',' order by a.grantee::regrole::text||a.privilege_type) from aclexplode(p.proacl) a), 'null') = 'postgres:EXECUTE,service_role:EXECUTE') then
    raise exception 'POSTFLIGHT D-19: crm.registrar_reingreso_lead_fn(uuid, text, jsonb) no quedó como se esperaba (cuerpo, definer, dueño, config o permisos)';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'crm.reservar_conversion_lead(uuid, text, text, jsonb)'::regprocedure
                  and md5(p.prosrc) = 'a2c2cf70925fced68f75e4d18d7b0da9'
                  and p.prosecdef = true and p.proowner = 'postgres'::regrole
                  and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path="",lock_timeout=5s'
                  and coalesce((select string_agg(a.grantee::regrole::text||':'||a.privilege_type, ',' order by a.grantee::regrole::text||a.privilege_type) from aclexplode(p.proacl) a), 'null') = 'authenticated:EXECUTE,postgres:EXECUTE') then
    raise exception 'POSTFLIGHT D-19: crm.reservar_conversion_lead(uuid, text, text, jsonb) no quedó como se esperaba (cuerpo, definer, dueño, config o permisos)';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'crm.saga_conversion_fn(text, jsonb)'::regprocedure
                  and md5(p.prosrc) = '58f723cd9f2b5b0a190c51797c1ec395'
                  and p.prosecdef = true and p.proowner = 'postgres'::regrole
                  and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path="",lock_timeout=5s'
                  and coalesce((select string_agg(a.grantee::regrole::text||':'||a.privilege_type, ',' order by a.grantee::regrole::text||a.privilege_type) from aclexplode(p.proacl) a), 'null') = 'authenticated:EXECUTE,postgres:EXECUTE') then
    raise exception 'POSTFLIGHT D-19: crm.saga_conversion_fn(text, jsonb) no quedó como se esperaba (cuerpo, definer, dueño, config o permisos)';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'private.enlazar_lead_reabierto(uuid, uuid)'::regprocedure
                  and md5(p.prosrc) = '891aa806bff7cd422013d95ab2d88d11'
                  and p.prosecdef = true and p.proowner = 'postgres'::regrole
                  and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path=""'
                  and coalesce((select string_agg(a.grantee::regrole::text||':'||a.privilege_type, ',' order by a.grantee::regrole::text||a.privilege_type) from aclexplode(p.proacl) a), 'null') = 'postgres:EXECUTE') then
    raise exception 'POSTFLIGHT D-19: private.enlazar_lead_reabierto(uuid, uuid) no quedó como se esperaba (cuerpo, definer, dueño, config o permisos)';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'private.trg_leads_zz_enlaza_identidad()'::regprocedure
                  and md5(p.prosrc) = '71807b0e2fa0b2cd8b2a5ca98dbf89a7'
                  and p.prosecdef = true and p.proowner = 'postgres'::regrole
                  and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path="",lock_timeout=5s'
                  and coalesce((select string_agg(a.grantee::regrole::text||':'||a.privilege_type, ',' order by a.grantee::regrole::text||a.privilege_type) from aclexplode(p.proacl) a), 'null') = 'postgres:EXECUTE') then
    raise exception 'POSTFLIGHT D-19: private.trg_leads_zz_enlaza_identidad() no quedó como se esperaba (cuerpo, definer, dueño, config o permisos)';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'private.trg_leads_zz_puente_identidad()'::regprocedure
                  and md5(p.prosrc) = '5e145a28199ca0db7ad31b67f1995e39'
                  and p.prosecdef = true and p.proowner = 'postgres'::regrole
                  and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path="",lock_timeout=5s'
                  and coalesce((select string_agg(a.grantee::regrole::text||':'||a.privilege_type, ',' order by a.grantee::regrole::text||a.privilege_type) from aclexplode(p.proacl) a), 'null') = 'postgres:EXECUTE') then
    raise exception 'POSTFLIGHT D-19: private.trg_leads_zz_puente_identidad() no quedó como se esperaba (cuerpo, definer, dueño, config o permisos)';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'private.trg_perfiles_documento_protegido()'::regprocedure
                  and md5(p.prosrc) = '7a7d3744136748fe72d10009482c3d59'
                  and p.prosecdef = true and p.proowner = 'postgres'::regrole
                  and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path=""'
                  and coalesce((select string_agg(a.grantee::regrole::text||':'||a.privilege_type, ',' order by a.grantee::regrole::text||a.privilege_type) from aclexplode(p.proacl) a), 'null') = 'postgres:EXECUTE') then
    raise exception 'POSTFLIGHT D-19: private.trg_perfiles_documento_protegido() no quedó como se esperaba (cuerpo, definer, dueño, config o permisos)';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'public.crear_contrato(jsonb, jsonb)'::regprocedure
                  and md5(p.prosrc) = '4bf2f691888bee4d3198cccba8acd396'
                  and p.prosecdef = true and p.proowner = 'postgres'::regrole
                  and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path=""'
                  and coalesce((select string_agg(a.grantee::regrole::text||':'||a.privilege_type, ',' order by a.grantee::regrole::text||a.privilege_type) from aclexplode(p.proacl) a), 'null') = 'authenticated:EXECUTE,postgres:EXECUTE,service_role:EXECUTE') then
    raise exception 'POSTFLIGHT D-19: public.crear_contrato(jsonb, jsonb) no quedó como se esperaba (cuerpo, definer, dueño, config o permisos)';
  end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('crm','private','public')
         and pg_catalog.strpos(p.prosrc, 'resolver_en_puertas') > 0
         and pg_catalog.strpos(p.prosrc, 'crm_flag_resolver_en_puertas') = 0
         and pg_catalog.strpos(p.prosrc, 'resolver_en_puertas_bajo_candado') = 0
         and p.prosrc ~* '(insert into|update |delete from)') <> 0 then
    raise exception 'POSTFLIGHT D-19: sigue habiendo funciones que ESCRIBEN y leen la bandera sin el candado compartido';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations where version = '20260906200000' and coalesce(name, '') <> 'crm_f2b_d19_toda_escritura_lee_la_bandera_bajo_su_candado') then
    raise exception 'REGISTRO D-19: la versión 20260906200000 ya está registrada con otro nombre';
  end if;
end
$chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20260906200000', 'crm_f2b_d19_toda_escritura_lee_la_bandera_bajo_su_candado', array['-- F2.b D-19 aplicada con db query --linked --file (md5 0efa2304d0402a1cd7f47bb3eb757760)'])
on conflict (version) do nothing;
commit;
