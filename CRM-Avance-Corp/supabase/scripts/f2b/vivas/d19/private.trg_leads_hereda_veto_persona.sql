CREATE OR REPLACE FUNCTION private.trg_leads_hereda_veto_persona()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  v_inv uuid;
  v_veto boolean;
begin
  if not coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    return new;
  end if;
  -- Solo DNI: crm.leads.dni es siempre DNI de 8 dígitos (contrato §18). Se
  -- normaliza igual que el resolver (este trigger corre ANTES del btrim de 00).
  if nullif(pg_catalog.btrim(coalesce(new.dni,'')), '') is null then
    return new;
  end if;
  -- Orden total: documento -> identidad -> (contactos los toma 00 después).
  perform private.identidad_bloquear_documento('DNI', new.dni);
  v_inv := private.inversionista_por_documento('DNI', new.dni);
  if v_inv is null then
    return new;
  end if;
  -- Serializa contra marcar/levantar_no_contactar (identidad FOR UPDATE) y relee.
  select i.no_contactar into v_veto
  from crm.inversionistas i
  where i.id = v_inv
  for update;
  if coalesce(v_veto, false) then
    raise exception 'La persona tiene la restricción «No insistir»: no se abre una oportunidad nueva'
      using errcode = 'P0429',
            detail = pg_catalog.jsonb_build_object('estado', 'no_contactar', 'via', 'identidad')::text;
  end if;
  return new;
end;
$function$
