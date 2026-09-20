-- Grant POR COLUMNA para crm.leads.alta_manual y crm.leads.creado_por.
--
-- Contexto: 20260919170500 (procedencia del lead) hace que crm.cartera_filtrada_fn
-- (SECURITY INVOKER) lea esas dos columnas para todo analista, y el front las pide
-- también en el select directo del ámbito. Hoy son legibles solo por el ACL de
-- TABLA (`authenticated=rw`, `service_role=arwd`, medido en producción el 19/09):
-- ninguna de las dos tiene ACL propia. La convención de la casa desde
-- 20260718000001 es que toda columna que el front o una RPC invoker necesite
-- lleve su grant explícito (P3 del auditor RLS, 19/09).
--
-- Lo que este grant VALE, dicho sin adornos (medido en el banco, PG 17, 19/09):
-- un `revoke select on crm.leads` de TABLA ARRASTRA las ACL por columna del
-- mismo privilegio (tenencia_desde pierde su `r`), así que el grant por columna
-- NO es una red contra «alguien revoca el grant de tabla». Su valor es de
-- convención y de registro: si algún día se pasa a privilegios por columna
-- (revoke de tabla + grant columna a columna), estas dos quedan DOCUMENTADAS
-- (aquí y en MIGRACIONES.md) como columnas a reponer, igual que las demás con
-- ACL propia; el catálogo no las recuerda tras el revoke, el repo sí. Las notas
-- de migraciones anteriores que prometen «la única red si alguien revoca el
-- grant de tabla» describen la intención, no la semántica de PostgreSQL.
--
-- Solo SELECT, mismo molde que tenencia_desde (20260725012707): las dos columnas
-- las escriben únicamente funciones SECURITY DEFINER (crm.crear_lead_si_disponible
-- y crm.importar_lead_fn) y el trigger private.leads_before_update las restaura
-- desde OLD en todo UPDATE. Ningún cliente puede FIJARLAS: authenticated no tiene
-- INSERT de tabla y un UPDATE suyo sobre ellas es un no-op silencioso.
-- No toca tablas, políticas, funciones, otros ACL ni objetos de public.
begin;
set local lock_timeout='10s';
do $preflight$
begin
  if (select count(*) from pg_attribute
      where attrelid='crm.leads'::regclass and attnum>0 and not attisdropped
        and attname in ('alta_manual','creado_por'))<>2 then
    raise exception 'PREFLIGHT: faltan las columnas alta_manual / creado_por en crm.leads';
  end if;
  -- Sin ACL propia todavía (medido en producción el 19/09): esta migración la crea.
  if exists (select 1 from pg_attribute
      where attrelid='crm.leads'::regclass and attname in ('alta_manual','creado_por')
        and coalesce(cardinality(attacl),0)>0) then
    raise exception 'PREFLIGHT: alta_manual / creado_por ya tienen ACL por columna; revisar antes de instalar';
  end if;
  -- Las dos escritoras siguen siendo SECURITY DEFINER: por eso basta SELECT.
  if (select count(*) from pg_proc
      where pronamespace='crm'::regnamespace
        and proname in ('crear_lead_si_disponible','importar_lead_fn') and prosecdef)<>2 then
    raise exception 'PREFLIGHT: una escritora de alta_manual no es SECURITY DEFINER; revisar el alcance del grant';
  end if;
end;
$preflight$;
create temporary table leads_grant_preflight on commit drop as
select c.relacl as tabla_acl,
  (select jsonb_object_agg(a.attname, a.attacl::text) from pg_attribute a
    where a.attrelid=c.oid and a.attnum>0 and not a.attisdropped
      and coalesce(cardinality(a.attacl),0)>0) as otras_columnas
from pg_class c where c.oid='crm.leads'::regclass;

grant select (alta_manual, creado_por) on crm.leads to authenticated, service_role;

do $postflight$
declare v_col text;
begin
  foreach v_col in array array['alta_manual','creado_por'] loop
    -- Exactamente dos entradas, SELECT para authenticated y service_role, nada más.
    if (select count(*) from pg_attribute a, aclexplode(a.attacl) e
        where a.attrelid='crm.leads'::regclass and a.attname=v_col)<>2
      or (select count(*) from pg_attribute a, aclexplode(a.attacl) e
        where a.attrelid='crm.leads'::regclass and a.attname=v_col
          and e.privilege_type='SELECT' and not e.is_grantable
          and e.grantee in ('authenticated'::regrole,'service_role'::regrole))<>2 then
      raise exception 'POSTFLIGHT: la ACL por columna de % no quedó como se esperaba',v_col;
    end if;
    if has_column_privilege('anon','crm.leads',v_col,'SELECT') then
      raise exception 'POSTFLIGHT: anon puede leer %',v_col;
    end if;
    if not has_column_privilege('authenticated','crm.leads',v_col,'SELECT')
      or not has_column_privilege('service_role','crm.leads',v_col,'SELECT') then
      raise exception 'POSTFLIGHT: % dejó de ser legible',v_col;
    end if;
  end loop;
  -- El ACL de TABLA y las demás ACL por columna no cambian.
  if (select relacl from pg_class where oid='crm.leads'::regclass)
       is distinct from (select tabla_acl from leads_grant_preflight)
    or (select jsonb_object_agg(a.attname, a.attacl::text) from pg_attribute a
        where a.attrelid='crm.leads'::regclass and a.attnum>0 and not a.attisdropped
          and coalesce(cardinality(a.attacl),0)>0
          and a.attname not in ('alta_manual','creado_por'))
       is distinct from (select otras_columnas from leads_grant_preflight) then
    raise exception 'POSTFLIGHT: cambió una ACL que esta migración no debía tocar';
  end if;
end;
$postflight$;
notify pgrst,'reload schema';
commit;
