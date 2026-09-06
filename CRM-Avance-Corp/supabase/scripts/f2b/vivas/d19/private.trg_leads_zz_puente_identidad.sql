CREATE OR REPLACE FUNCTION private.trg_leads_zz_puente_identidad()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  v_priv boolean := coalesce(pg_catalog.current_setting('crm.op_privilegiada', true) = 'on', false);
begin
  -- «UPDATE OF columna» mira la lista SET de la sentencia, no el valor: un BEFORE
  -- que fija inversionista_id no lo dispararía. Por eso AFTER INSERT OR UPDATE
  -- con comparación de valor.
  if tg_op = 'UPDATE' and new.inversionista_id is not distinct from old.inversionista_id then
    return null;
  end if;
  if new.inversionista_id is null then
    return null;
  end if;
  if not coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    return null;
  end if;
  if exists (select 1 from crm.inversionista_leads il where il.lead_id = new.id) then
    -- Reapuntes de puente (fusión) los gestiona su propia puerta bajo válvula.
    if v_priv then
      return null;
    end if;
    if exists (select 1 from crm.inversionista_leads il
               where il.lead_id = new.id and il.inversionista_id <> new.inversionista_id) then
      raise exception 'El puente persona<->lead no coincide con el enlace del lead' using errcode = 'P0409';
    end if;
    return null;
  end if;
  if exists (select 1 from crm.inversionista_leads il
             where il.inversionista_id = new.inversionista_id and il.rol = 'canonico' and il.lead_id <> new.id) then
    raise exception 'La persona ya tiene un lead canónico' using errcode = 'P0409';
  end if;
  insert into crm.inversionista_leads (inversionista_id, lead_id, rol)
  values (new.inversionista_id, new.id, 'canonico');
  return null;
end;
$function$
