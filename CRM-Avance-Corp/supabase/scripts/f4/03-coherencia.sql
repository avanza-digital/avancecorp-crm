create or replace function private.f4_sincronizar_cierre()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_inversion uuid;
begin
  update crm.inversiones i set empresa_id=e.id,
    estado=case when new.anulado_en is null then 'vigente' else 'anulada' end
  from crm.empresas e where i.cierre_externo_id=new.id and e.clave=new.cooperativa
  returning i.id into v_inversion;
  if v_inversion is not null and not new.es_cierre_inicial then
    insert into crm.inversion_eventos(inversion_id,tipo,motivo,creado_por)
    values(v_inversion,
      case when old.anulado_en is null and new.anulado_en is not null then 'anulacion' else 'correccion' end,
      case when old.anulado_en is null and new.anulado_en is not null then new.motivo_anulacion else 'Corrección de cierre externo' end,
      (select auth.uid()));
  end if;
  return new;
end;
$$;
revoke all on function private.f4_sincronizar_cierre() from public,anon,authenticated,service_role;
create trigger trg_cierres_f4_sincronizar after update of monto,moneda,cooperativa,
  numero_transaccion,referencia_externa,vence_en,nota,anulado_en on crm.cierres_externos
  for each row execute function private.f4_sincronizar_cierre();

-- Solo después de adaptar los lectores en la MISMA transacción puede dejar de
-- ser única la relación económica. La conversión inicial continúa siendo única.
alter table crm.cierres_externos drop constraint cierres_externos_un_cierre_por_lead;
create unique index cierres_externos_inicial_por_lead_uidx
  on crm.cierres_externos(lead_id) where es_cierre_inicial;
create index cierres_externos_lead_idx on crm.cierres_externos(lead_id);
create index cierres_externos_comprobante_idx on crm.cierres_externos(comprobante_objeto_id);
create index cierres_externos_fecha_imputacion_idx on crm.cierres_externos(fecha_imputacion)
  where fecha_imputacion is not null;
