CREATE OR REPLACE FUNCTION private.leads_protege_inversionista_id()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_priv boolean := coalesce(pg_catalog.current_setting('crm.op_privilegiada', true) = 'on', false);
begin
  if not v_priv then
    if tg_op = 'INSERT' then
      new.inversionista_id := null;
    else
      new.inversionista_id := old.inversionista_id;
    end if;
  end if;
  return new;
end $function$

