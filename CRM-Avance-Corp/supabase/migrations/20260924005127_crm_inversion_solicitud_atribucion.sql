-- Venta cruzada · Fase 1 (2 de 2): la solicitud guarda desde el inicio quién vende.
--
-- QUÉ HACE. Añade a crm.inversion_solicitudes:
--   puerta              'cartera' (todo lo que existe hoy) o 'cliente_existente'
--                       (venta cruzada: un analista registra la inversión de un
--                       cliente cuyo responsable es otro).
--   analista_cierre_id  analista al que pertenecerá la inversión. Solo en venta
--                       cruzada, y es SIEMPRE quien la registra (creado_por): la
--                       base lo exige; ninguna pantalla lo elige (decisión D1).
--   motivo_atribucion   por qué la registra alguien que no es el responsable
--                       (D1: motivo corto obligatorio). Se enmascara en la auditoría.
--   busqueda_id         la búsqueda que abrió la puerta. La base exige que sea
--                       propia, por documento, con veredicto «encontrado», de esta
--                       misma persona (canónica) y de las últimas 2 horas.
-- y sus reglas: coherencia por puerta, inmutables desde el alta (también la
-- persona de una venta cruzada) y un solo borrador de venta cruzada por persona y
-- empresa (decisión D6).
--
-- POR QUÉ. Hoy la atribución se deduce del responsable al confirmar
-- (private.inversion_validar_datos L88-91 y crm.confirmar_inversion_revisada_fn
-- L130-144, cuerpos vivos del 23/09). La venta cruzada necesita que el analista
-- quede decidido por el servidor y CONGELADO en la solicitud antes de confirmar,
-- separado del responsable de la relación, que no cambia. La auditoría RLS del
-- 23/09 pidió además atar la venta a su búsqueda en la propia base y no dejar el
-- motivo, texto libre, en claro en public.audit_log (lo lee cualquier es_admin()).
--
-- CONDUCTA. ADITIVA. Las solicitudes actuales quedan en 'cartera' con las columnas
-- nuevas en NULL, que es exactamente la regla de hoy. Ninguna función existente
-- lee ni escribe estas columnas todavía (lo harán las Fases 3 y 4, que se publican
-- después de esta y juntas). El trigger de auditoría se recrea con el mismo nombre,
-- momento y verbos, enmascarando además motivo_atribucion.
--
-- REVERSA. supabase/scripts/venta-cruzada/reversa-fase1.sql (falla cerrada si ya
-- existe alguna solicitud de venta cruzada o alguna función que dependa de esto).
begin;
set local lock_timeout = '5s';

do $pre$ begin
  if to_regclass('crm.busquedas_cliente_existente') is null
     or to_regprocedure('private.busqueda_cliente_es_llave(uuid,uuid,uuid)') is null then
    raise exception 'Falta la bitácora de búsquedas (20260924005126): aplica primero esa migración';
  end if;
  if exists (select 1 from information_schema.columns
             where table_schema = 'crm' and table_name = 'inversion_solicitudes'
               and column_name in ('puerta','analista_cierre_id','motivo_atribucion','busqueda_id')) then
    raise exception 'Las columnas de atribución ya existen: esta migración ya se aplicó';
  end if;
  -- Ancla: el auditor de la tabla es el de hoy, al byte.
  if (select pg_get_triggerdef(t.oid) from pg_trigger t
      where t.tgrelid = 'crm.inversion_solicitudes'::regclass and t.tgname = 'trg_audit_inversion_solicitudes')
     is distinct from 'CREATE TRIGGER trg_audit_inversion_solicitudes AFTER INSERT OR DELETE OR UPDATE ON crm.inversion_solicitudes FOR EACH ROW EXECUTE FUNCTION private.log_audit_sin_secretos(''datos'', ''auth_contexto'')' then
    raise exception 'La base cambió: trg_audit_inversion_solicitudes no es el de hoy. Revisa antes de instalar.';
  end if;
end $pre$;

-- ---------------------------------------------------------------------------
-- 1. Columnas e índices
-- ---------------------------------------------------------------------------
alter table crm.inversion_solicitudes
  add column puerta text not null default 'cartera',
  add column analista_cierre_id uuid references public.perfiles(id),
  add column motivo_atribucion text,
  add column busqueda_id uuid references crm.busquedas_cliente_existente(id);

create index inversion_solicitudes_analista_idx
  on crm.inversion_solicitudes (analista_cierre_id) where analista_cierre_id is not null;
create index inversion_solicitudes_busqueda_idx
  on crm.inversion_solicitudes (busqueda_id) where busqueda_id is not null;
-- D6: una sola venta cruzada en preparación por persona y empresa. Es la red de la
-- base; la puerta (Fase 4) compara además por persona CANÓNICA bajo candado,
-- porque tras una fusión dos ids de origen serían la misma persona.
create unique index inversion_solicitud_cruzada_pendiente
  on crm.inversion_solicitudes (inversionista_id, empresa_id)
  where puerta = 'cliente_existente' and estado = 'preparada';

-- ---------------------------------------------------------------------------
-- 2. Reglas
-- ---------------------------------------------------------------------------
alter table crm.inversion_solicitudes
  add constraint inversion_solicitud_puerta_valida
    check (puerta in ('cartera','cliente_existente')),
  -- 'cartera' conserva la regla de hoy: ningún dato de atribución propio.
  -- 'cliente_existente' nunca convierte un lead, siempre trae analista, búsqueda y
  -- motivo, y la venta es de quien la registra.
  add constraint inversion_solicitud_atribucion_coherente check (
    (puerta = 'cartera'
      and analista_cierre_id is null and motivo_atribucion is null and busqueda_id is null)
    or (puerta = 'cliente_existente'
      and lead_origen_id is null
      and analista_cierre_id is not null
      and analista_cierre_id = creado_por
      and busqueda_id is not null
      and motivo_atribucion is not null
      and char_length(btrim(motivo_atribucion, E' \t\r\n')) between 10 and 500));

-- La llave: solo una búsqueda propia, por documento, «encontrado», de esta misma
-- persona y reciente abre una venta cruzada. Security invoker: solo la disparan
-- inserciones del dueño (las funciones security definer de las puertas).
create function private.inversion_venta_cruzada_llave()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  -- La regla vive en UNA función (20260924005126), la misma que usa la autorización.
  if not private.busqueda_cliente_es_llave(new.busqueda_id, new.creado_por, new.inversionista_id) then
    raise exception 'La venta cruzada exige una búsqueda propia, reciente y por documento de esta misma persona'
      using errcode = '22023';
  end if;
  return new;
end $$;
revoke all on function private.inversion_venta_cruzada_llave() from public, anon, authenticated, service_role;

create trigger inversion_solicitud_venta_cruzada_llave before insert
  on crm.inversion_solicitudes
  for each row when (new.puerta = 'cliente_existente')
  execute function private.inversion_venta_cruzada_llave();

-- Security invoker: solo compara NEW con OLD.
create function private.inversion_atribucion_inmutable()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if new.puerta is distinct from old.puerta
     or new.analista_cierre_id is distinct from old.analista_cierre_id
     or new.motivo_atribucion is distinct from old.motivo_atribucion
     or new.busqueda_id is distinct from old.busqueda_id
     or (old.puerta = 'cliente_existente' and new.inversionista_id is distinct from old.inversionista_id) then
    raise exception 'La atribución de una solicitud es inmutable: cancélala y registra otra'
      using errcode = '22023';
  end if;
  return new;
end $$;
revoke all on function private.inversion_atribucion_inmutable() from public, anon, authenticated, service_role;

create trigger inversion_solicitud_atribucion_inmutable before update
  on crm.inversion_solicitudes
  for each row execute function private.inversion_atribucion_inmutable();

-- ---------------------------------------------------------------------------
-- 3. Auditoría: mismo trigger, que ahora también enmascara el motivo
-- ---------------------------------------------------------------------------
drop trigger trg_audit_inversion_solicitudes on crm.inversion_solicitudes;
create trigger trg_audit_inversion_solicitudes after insert or update or delete
  on crm.inversion_solicitudes
  for each row execute function private.log_audit_sin_secretos('datos','auth_contexto','motivo_atribucion');

-- ---------------------------------------------------------------------------
-- 4. Comentarios
-- ---------------------------------------------------------------------------
comment on column crm.inversion_solicitudes.puerta is
  'Por dónde nació la solicitud: cartera (flujo del responsable y conversión de lead, regla de siempre) o cliente_existente (venta cruzada). Inmutable.';
comment on column crm.inversion_solicitudes.analista_cierre_id is
  'Venta cruzada: analista al que pertenecerá la inversión; siempre igual a creado_por (quien la registró). NULL en cartera, donde la atribución sigue saliendo del responsable. Inmutable.';
comment on column crm.inversion_solicitudes.motivo_atribucion is
  'Venta cruzada: por qué registra la inversión alguien que no es el responsable del cliente (10 a 500 caracteres). Texto libre: se enmascara en public.audit_log. Inmutable.';
comment on column crm.inversion_solicitudes.busqueda_id is
  'Venta cruzada: búsqueda propia, por documento, «encontrado», de esta misma persona y de las últimas 2 horas que abrió la puerta. Inmutable.';
comment on function private.inversion_venta_cruzada_llave() is
  'Trigger: una venta cruzada solo nace de una búsqueda propia, por documento, «encontrado», de esta misma persona (canónica) y de las últimas 2 horas.';
comment on function private.inversion_atribucion_inmutable() is
  'Trigger: puerta, analista_cierre_id, motivo_atribucion y busqueda_id no cambian después del alta; en venta cruzada tampoco la persona.';
comment on index crm.inversion_solicitud_cruzada_pendiente is
  'Decisión D6: una sola venta cruzada en preparación por persona y empresa.';

-- ---------------------------------------------------------------------------
-- 5. Postflight
-- ---------------------------------------------------------------------------
do $post$ begin
  if exists (select 1 from crm.inversion_solicitudes
             where puerta <> 'cartera' or analista_cierre_id is not null
                or motivo_atribucion is not null or busqueda_id is not null) then
    raise exception 'POSTFLIGHT: alguna solicitud existente quedó fuera de la regla de hoy';
  end if;
  if (select count(*) from pg_trigger
      where tgrelid = 'crm.inversion_solicitudes'::regclass and not tgisinternal) <> 5 then
    raise exception 'POSTFLIGHT: crm.inversion_solicitudes debía quedar con sus 3 triggers de antes más los 2 nuevos';
  end if;
  if (select pg_get_triggerdef(t.oid) from pg_trigger t
      where t.tgrelid = 'crm.inversion_solicitudes'::regclass and t.tgname = 'trg_audit_inversion_solicitudes')
     is distinct from 'CREATE TRIGGER trg_audit_inversion_solicitudes AFTER INSERT OR DELETE OR UPDATE ON crm.inversion_solicitudes FOR EACH ROW EXECUTE FUNCTION private.log_audit_sin_secretos(''datos'', ''auth_contexto'', ''motivo_atribucion'')' then
    raise exception 'POSTFLIGHT: el auditor de crm.inversion_solicitudes no quedó como se esperaba';
  end if;
  if exists (select 1 from private.tablas_sin_rastro() t where t.tabla = 'crm.inversion_solicitudes') then
    raise exception 'POSTFLIGHT: crm.inversion_solicitudes perdió su rastro de auditoría';
  end if;
end $post$;

commit;
