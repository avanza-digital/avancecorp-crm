CREATE OR REPLACE FUNCTION private.trg_leads_hereda_veto_persona()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_veto boolean;
begin
  if not coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    return new;
  end if;
  if new.no_contactar then
    return new;
  end if;
  -- Solo el documento exacto vincula (contrato #8). Lectura sin lock: no cambia
  -- el orden de locks (es un SELECT), no hay ciclo posible. Se NORMALIZA igual
  -- que el resolver (este trigger corre ANTES de que disponibilidad haga btrim).
  -- Solo DNI: crm.leads.dni es siempre DNI de 8 digitos (lo exige el trigger de
  -- alta; contrato §18: CE/pasaporte se resuelven al convertir).
  if new.dni is not null then
    select i.no_contactar into v_veto
    from crm.inversionista_identificadores idf
    join crm.inversionistas i on i.id = idf.inversionista_id
    where idf.tipo_documento = 'DNI'
      and idf.documento_normalizado = pg_catalog.upper(pg_catalog.regexp_replace(coalesce(new.dni,''), '[^A-Za-z0-9]', '', 'g'))
      and idf.estado = 'vigente'
      and i.estado <> 'fusionado'
    limit 1;
    if coalesce(v_veto, false) then
      new.no_contactar := true;
    end if;
  end if;
  return new;
end;
$function$

