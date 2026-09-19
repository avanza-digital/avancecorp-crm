-- Reversa de 20260919211105: retira la ACL por columna de alta_manual y
-- creado_por en crm.leads. Las columnas vuelven a depender del ACL de TABLA,
-- como antes; por eso el postflight exige que sigan legibles: si el ACL de
-- tabla ya no las cubriera, revertir dejaría la pantalla Leads en 42501 y esta
-- reversa se niega. No toca datos, funciones ni políticas.
begin;
set local lock_timeout='10s';
do $preflight$
declare v_col text;
begin
  foreach v_col in array array['alta_manual','creado_por'] loop
    if (select count(*) from pg_attribute a, aclexplode(a.attacl) e
        where a.attrelid='crm.leads'::regclass and a.attname=v_col)<>2
      or (select count(*) from pg_attribute a, aclexplode(a.attacl) e
        where a.attrelid='crm.leads'::regclass and a.attname=v_col
          and e.privilege_type='SELECT' and not e.is_grantable
          and e.grantee in ('authenticated'::regrole,'service_role'::regrole))<>2 then
      raise exception 'REVERSA: la ACL por columna de % no es la publicada por 20260919211105',v_col;
    end if;
  end loop;
end;
$preflight$;
create temporary table leads_grant_reversa on commit drop as
select c.relacl as tabla_acl,
  (select jsonb_object_agg(a.attname, a.attacl::text) from pg_attribute a
    where a.attrelid=c.oid and a.attnum>0 and not a.attisdropped
      and coalesce(cardinality(a.attacl),0)>0
      and a.attname not in ('alta_manual','creado_por')) as otras_columnas
from pg_class c where c.oid='crm.leads'::regclass;

revoke select (alta_manual, creado_por) on crm.leads from authenticated, service_role;

do $postflight$
declare v_col text;
begin
  foreach v_col in array array['alta_manual','creado_por'] loop
    if exists (select 1 from pg_attribute where attrelid='crm.leads'::regclass
        and attname=v_col and coalesce(cardinality(attacl),0)>0) then
      raise exception 'REVERSA: % conserva ACL por columna',v_col;
    end if;
    -- Siguen legibles por el ACL de tabla para los DOS roles (el estado anterior
    -- a 20260919211105); misma simetría que el postflight de la migración.
    if not has_column_privilege('authenticated','crm.leads',v_col,'SELECT')
      or not has_column_privilege('service_role','crm.leads',v_col,'SELECT') then
      raise exception 'REVERSA: % dejaría de ser legible (el ACL de tabla ya no cubre); no se revierte',v_col;
    end if;
  end loop;
  if (select relacl from pg_class where oid='crm.leads'::regclass)
       is distinct from (select tabla_acl from leads_grant_reversa)
    or (select jsonb_object_agg(a.attname, a.attacl::text) from pg_attribute a
        where a.attrelid='crm.leads'::regclass and a.attnum>0 and not a.attisdropped
          and coalesce(cardinality(a.attacl),0)>0
          and a.attname not in ('alta_manual','creado_por'))
       is distinct from (select otras_columnas from leads_grant_reversa) then
    raise exception 'REVERSA: cambió una ACL ajena';
  end if;
end;
$postflight$;
notify pgrst,'reload schema';
commit;
