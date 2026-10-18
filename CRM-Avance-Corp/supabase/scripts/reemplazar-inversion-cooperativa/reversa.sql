-- Reversa de 20261018053228_crm_reemplazar_inversion_cooperativa.sql. Retira las cinco funciones nuevas y devuelve los dos
-- ayudantes del bucket (private.f4_comprobante_autorizado, private.f4_comprobante_visible) a su cuerpo de producción
-- (copiado aquí desde produccion/*.sql; huella del preflight de la migración). Las copias «reemplazada por» de crm.inversiones_eliminadas y las
-- inversiones ya reemplazadas quedan como historia: la reversa no deshace reemplazos hechos. Se niega si otra función viva
-- llama a alguna de las cinco (nombre en minúsculas, sin comillas; una llamada armada con EXECUTE no se ve: revisar a mano).
-- Revertir primero el front (la pantalla llama a las dos puertas). Aplicar en UN mensaje (`db query --linked --file`).
begin;
set local lock_timeout = '5s';
select pg_advisory_lock(hashtext('crm_migracion_funciones'));
commit;

begin;
set local lock_timeout = '10s';
set local statement_timeout = '60s';
set local search_path = '';
set local quote_all_identifiers = off;

do $preflight$
begin
  if (select pg_catalog.string_agg(p.oid::regprocedure::text || '=' || md5(pg_catalog.pg_get_functiondef(p.oid)), ',' order by p.oid::regprocedure::text)
      from pg_catalog.pg_proc p
      where p.oid in ('private.f4_comprobante_autorizado(text)'::regprocedure, 'private.f4_comprobante_visible(text)'::regprocedure))
     is distinct from 'private.f4_comprobante_autorizado(text)=cdecad21e77c38d023ba156efd8faa74,'
                      'private.f4_comprobante_visible(text)=d5e74abf371a35c677d42da9abb2ff82' then
    raise exception 'REVERSA reemplazar_cooperativa: los ayudantes del bucket no tienen la huella que dejó la migración';
  end if;
  if exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
             where n.nspname in ('crm', 'private', 'public')
               and p.oid not in ('private.f4_comprobante_autorizado(text)'::regprocedure,
                                 'crm.reemplazar_inversion_cooperativa_fn(uuid,text,jsonb)'::regprocedure,
                                 'private.reemplazar_inversion_cooperativa(uuid,jsonb,uuid,text,jsonb)'::regprocedure)
               and (p.prosrc ~ 'reemplazar_inversion_cooperativa' or p.prosrc ~ 'registrar_inversion_reemplazada_cooperativa'
                    or p.prosrc ~ 'f4_comprobante_reemplazo_autorizado')) then
    raise exception 'REVERSA reemplazar_cooperativa: otra función viva llama a lo que se retira; revisar antes';
  end if;
end
$preflight$;

drop function crm.reemplazar_inversion_cooperativa_vista_previa_fn(uuid, date);
drop function crm.reemplazar_inversion_cooperativa_fn(uuid, text, jsonb);
drop function private.reemplazar_inversion_cooperativa(uuid, jsonb, uuid, text, jsonb);
drop function private.registrar_inversion_reemplazada_cooperativa(jsonb, uuid, text, text, uuid, jsonb);

-- Los dos ayudantes vuelven a su cuerpo de producción (copiado de produccion/*.sql: `db query --file` no entiende \ir).
-- CREATE OR REPLACE conserva dueño, ACL y SECURITY.
CREATE OR REPLACE FUNCTION private.f4_comprobante_autorizado(p_ruta text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare v_persona uuid; v_solicitud uuid; v_ctx jsonb; v_s crm.inversion_solicitudes%rowtype;
begin
  if p_ruta is null or p_ruta !~ '^[a-f0-9-]{36}/[a-f0-9-]{36}/[a-zA-Z0-9_-]+\.(pdf|jpg|jpeg|png)$' then return false; end if;
  begin v_persona:=split_part(p_ruta,'/',1)::uuid; v_solicitud:=split_part(p_ruta,'/',2)::uuid;
  exception when invalid_text_representation then return false; end;
  v_ctx:=private.inversion_persona_contexto_para(v_persona,(select lead_origen_id from crm.inversion_solicitudes where id=v_solicitud),v_solicitud,null::uuid);
  select * into v_s from crm.inversion_solicitudes where id=v_solicitud for share;
  return found and v_s.inversionista_id=v_persona and v_s.estado='preparada'
    and (v_s.puerta='cliente_existente' or v_s.responsable_esperado_id=(v_ctx->>'responsable_id')::uuid)
    and private.venta_cruzada_opera(v_solicitud)
    and v_s.datos#>>'{evidencia,ruta}'=p_ruta;
exception when insufficient_privilege or lock_not_available or sqlstate 'P0409' or sqlstate 'P0429' then return false;
end;
$function$

;
CREATE OR REPLACE FUNCTION private.f4_comprobante_visible(p_ruta text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(private.rol_crm((select auth.uid())) in ('vendedor','supervisor','gerencia') and exists (
    select 1 from crm.inversion_solicitudes s join crm.inversionistas i on i.id=private.inversionista_canonica(s.inversionista_id)
    where s.datos#>>'{evidencia,ruta}'=p_ruta and (
      private.rol_crm((select auth.uid()))='gerencia'
      or i.responsable_relacion_id in (select private.vendedor_ids_visibles((select auth.uid())))
      or (s.puerta='cliente_existente' and s.analista_cierre_id in (select private.vendedor_ids_visibles((select auth.uid()))))
    )
  ),false);
$function$

;
drop function private.f4_comprobante_reemplazo_autorizado(text);
comment on function private.f4_comprobante_autorizado(text) is null;
comment on function private.f4_comprobante_visible(text) is null;

do $postflight$
begin
  if (select pg_catalog.string_agg(p.oid::regprocedure::text || '=' || md5(pg_catalog.pg_get_functiondef(p.oid)), ',' order by p.oid::regprocedure::text)
      from pg_catalog.pg_proc p
      where p.oid in ('private.f4_comprobante_autorizado(text)'::regprocedure, 'private.f4_comprobante_visible(text)'::regprocedure))
     is distinct from 'private.f4_comprobante_autorizado(text)=7cdb9ea79f143edf53f0663b2d37aeae,'
                      'private.f4_comprobante_visible(text)=45fb7ff24d69f7a685cdc45902aedf9e' then
    raise exception 'REVERSA reemplazar_cooperativa: los ayudantes del bucket no volvieron a su huella anterior';
  end if;
  if to_regprocedure('crm.reemplazar_inversion_cooperativa_fn(uuid,text,jsonb)') is not null
     or to_regprocedure('private.f4_comprobante_reemplazo_autorizado(text)') is not null then
    raise exception 'REVERSA reemplazar_cooperativa: quedó alguna función nueva';
  end if;
end
$postflight$;

commit;
select pg_advisory_unlock(hashtext('crm_migracion_funciones'));
