CREATE OR REPLACE FUNCTION private.enlazar_lead_reabierto(p_lead_id uuid, p_inv uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_previo text;
begin
  if p_inv is null or not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    return;
  end if;
  v_previo := coalesce(pg_catalog.current_setting('crm.op_privilegiada', true), 'off');
  perform pg_catalog.set_config('crm.op_privilegiada', 'on', true);
  update crm.leads set inversionista_id = p_inv where id = p_lead_id and inversionista_id is null;
  update crm.inversionista_leads il set rol = 'canonico'
   where il.lead_id = p_lead_id and il.rol = 'historico'
     and not exists (select 1 from crm.inversionista_leads il2 where il2.inversionista_id = il.inversionista_id and il2.rol = 'canonico');
  perform pg_catalog.set_config('crm.op_privilegiada', v_previo, true);
end;
$function$
