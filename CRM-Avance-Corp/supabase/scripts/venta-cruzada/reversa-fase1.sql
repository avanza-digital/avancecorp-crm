-- Venta cruzada · reversa de la Fase 1.
-- Retira, en orden inverso, 20260924005127_crm_inversion_solicitud_atribucion y
-- 20260924005126_crm_busquedas_cliente_existente. Sirve también si solo quedó
-- aplicada la primera (cada migración confirma por separado).
-- Falla cerrada si: ya existe alguna solicitud de venta cruzada o alguna búsqueda
-- registrada (hay que exportarlas y decidir antes), o alguna función de fases
-- posteriores depende de estos objetos (hay que retirar antes esas fases).
-- El veredicto viaja como FILA al final, porque `db query` no transporta avisos.
begin;
set local lock_timeout = '5s';

do $pre$
declare v_b boolean := to_regclass('crm.busquedas_cliente_existente') is not null;
  v_c boolean := exists (select 1 from information_schema.columns
    where table_schema = 'crm' and table_name = 'inversion_solicitudes' and column_name = 'puerta');
begin
  if not v_b and not v_c then
    raise exception 'REVERSA: la Fase 1 no está aplicada';
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             where n.nspname in ('crm','private','public')
               and p.proname not in ('busqueda_cliente_inmutable','busqueda_cliente_es_llave',
                                     'inversion_atribucion_inmutable','inversion_venta_cruzada_llave')
               and (p.prosrc like '%busquedas_cliente_existente%' or p.prosrc like '%motivo_atribucion%'
                    or p.prosrc like '%''cliente_existente''%')) then
    raise exception 'REVERSA: hay funciones de fases posteriores que dependen de la Fase 1; retíralas antes';
  end if;
  -- IF anidados a propósito: plpgsql prepara cada consulta al ejecutarla, y una
  -- condición combinada fallaría al preparar si la columna o la tabla no existen.
  if v_c then
    if exists (select 1 from crm.inversion_solicitudes where puerta <> 'cartera') then
      raise exception 'REVERSA: hay solicitudes de venta cruzada; revísalas antes de retirar la Fase 1';
    end if;
  end if;
  if v_b then
    if exists (select 1 from crm.busquedas_cliente_existente) then
      raise exception 'REVERSA: la bitácora tiene búsquedas registradas; expórtalas antes de retirarla';
    end if;
  end if;
end $pre$;

-- 20260924005127 (solo si está aplicada)
do $m2$ begin
  if exists (select 1 from information_schema.columns
             where table_schema = 'crm' and table_name = 'inversion_solicitudes' and column_name = 'puerta') then
    drop trigger trg_audit_inversion_solicitudes on crm.inversion_solicitudes;
    create trigger trg_audit_inversion_solicitudes after insert or update or delete
      on crm.inversion_solicitudes
      for each row execute function private.log_audit_sin_secretos('datos','auth_contexto');
    drop trigger inversion_solicitud_atribucion_inmutable on crm.inversion_solicitudes;
    drop trigger inversion_solicitud_venta_cruzada_llave on crm.inversion_solicitudes;
    drop function private.inversion_atribucion_inmutable();
    drop function private.inversion_venta_cruzada_llave();
    drop index crm.inversion_solicitud_cruzada_pendiente;
    drop index crm.inversion_solicitudes_analista_idx;
    drop index crm.inversion_solicitudes_busqueda_idx;
    alter table crm.inversion_solicitudes
      drop constraint inversion_solicitud_atribucion_coherente,
      drop constraint inversion_solicitud_puerta_valida;
    alter table crm.inversion_solicitudes
      drop column busqueda_id,
      drop column motivo_atribucion,
      drop column analista_cierre_id,
      drop column puerta;
  end if;
end $m2$;

-- 20260924005126 (la tabla se lleva sus triggers e índices)
do $m1$ begin
  if to_regclass('crm.busquedas_cliente_existente') is not null then
    drop function if exists private.busqueda_cliente_es_llave(uuid,uuid,uuid);
    drop table crm.busquedas_cliente_existente;
    drop function private.busqueda_cliente_inmutable();
  end if;
end $m1$;

do $post$ begin
  if (select count(*) from pg_trigger
      where tgrelid = 'crm.inversion_solicitudes'::regclass and not tgisinternal) <> 3 then
    raise exception 'REVERSA: crm.inversion_solicitudes debía volver a sus 3 triggers';
  end if;
  if (select pg_get_triggerdef(t.oid) from pg_trigger t
      where t.tgrelid = 'crm.inversion_solicitudes'::regclass and t.tgname = 'trg_audit_inversion_solicitudes')
     is distinct from 'CREATE TRIGGER trg_audit_inversion_solicitudes AFTER INSERT OR DELETE OR UPDATE ON crm.inversion_solicitudes FOR EACH ROW EXECUTE FUNCTION private.log_audit_sin_secretos(''datos'', ''auth_contexto'')' then
    raise exception 'REVERSA: el auditor de crm.inversion_solicitudes no volvió a su definición de antes';
  end if;
  if to_regclass('crm.busquedas_cliente_existente') is not null
     or to_regprocedure('private.busqueda_cliente_inmutable()') is not null then
    raise exception 'REVERSA: quedaron restos de la bitácora';
  end if;
end $post$;

commit;
select 'REVERSA_FASE1_OK' as veredicto;
