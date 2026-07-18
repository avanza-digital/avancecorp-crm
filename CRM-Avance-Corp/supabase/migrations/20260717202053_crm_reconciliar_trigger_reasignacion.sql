-- Fase 0A: hace reproducible el emisor de actividades de reasignacion que ya
-- existe en produccion. Esta migracion NO amplia su semantica: solo observa
-- cambios de vendedor_id en UPDATE, igual que el comportamiento vigente.

create or replace function private.trg_leads_reasignacion()
returns trigger
language plpgsql
security definer
set search_path to 'crm', 'private', 'public'
as $function$
declare
  v_old text;
  v_new text;
begin
  if new.vendedor_id is distinct from old.vendedor_id then
    select nombre_completo into v_old from public.perfiles where id = old.vendedor_id;
    select nombre_completo into v_new from public.perfiles where id = new.vendedor_id;
    insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)
    values (
      new.id, 'reasignacion',
      coalesce(v_old, 'Sin asignar') || ' → ' || coalesce(v_new, 'Sin asignar'),
      jsonb_build_object('vendedor_anterior', old.vendedor_id, 'vendedor_nuevo', new.vendedor_id),
      coalesce((select auth.uid()), new.creado_por)
    );
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_leads_reasignacion on crm.leads;

create trigger trg_leads_reasignacion
before update on crm.leads
for each row
execute function private.trg_leads_reasignacion();
