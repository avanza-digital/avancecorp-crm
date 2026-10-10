CREATE OR REPLACE FUNCTION private.inversionista_canonica(p_id uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with recursive c as (
    select i.id, i.inversionista_canonico_id, 1 as n from crm.inversionistas i where i.id = p_id
    union all
    select i.id, i.inversionista_canonico_id, c.n + 1
    from c join crm.inversionistas i on i.id = c.inversionista_canonico_id
    where c.n < 16
  )
  select case when p_id is null then null
              else coalesce((select c.id from c where c.inversionista_canonico_id is null order by c.n desc limit 1), p_id) end
$function$
