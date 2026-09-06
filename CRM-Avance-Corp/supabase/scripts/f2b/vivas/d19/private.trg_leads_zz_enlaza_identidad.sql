CREATE OR REPLACE FUNCTION private.trg_leads_zz_enlaza_identidad()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  v_priv boolean := coalesce(pg_catalog.current_setting('crm.op_privilegiada', true) = 'on', false);
  v_inv uuid;
  v_otro record;
begin
  if not coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    return new;
  end if;
  if tg_op = 'UPDATE' then
    if new.dni is not distinct from old.dni or v_priv then
      return new;
    end if;
    -- En UPDATE la fila del lead YA está bloqueada: aquí no se toma ningún lock de
    -- identidad (evitaría el orden documento->identidad->lead y podría abrazarse con
    -- marcar/levantar y la conversión). Se RECHAZA, no se enlaza: el documento de una
    -- persona enlazada, o un documento que resuelve a una persona reconocida, solo
    -- cambia por la corrección de Gerencia (bajo válvula, b5). Un DNI que no resuelve
    -- a nadie sigue editándose como hoy.
    if old.inversionista_id is not null
       or exists (select 1 from crm.inversionista_leads il where il.lead_id = new.id) then
      raise exception 'El documento pertenece a una persona reconocida: solo Gerencia lo corrige (corrección de documento)'
        using errcode = 'P0409';
    end if;
    -- F2.b [D-13] (Codex v3 B1, auditor v4 A1): con la identidad encendida, el DNI de un lead se FIJA por su puerta
    -- (crm.fijar_dni_lead_fn), que toma el candado del documento y a la persona ANTES de la fila (orden documento ->
    -- persona -> lead), juzga a la persona y enlaza si procede: por la puerta, el trigger deja pasar. El UPDATE directo
    -- (fila ya bloqueada, sin serialización posible con una reserva en vuelo) se rechaza: hacia una persona reconocida
    -- con el mensaje de siempre; hacia un documento sin dueño, «por su puerta».
    if coalesce(pg_catalog.current_setting('crm.dni_por_puerta', true), 'off') = 'on' then
      return new;
    end if;
    if nullif(pg_catalog.btrim(coalesce(new.dni,'')), '') is not null
       and private.inversionista_por_documento('DNI', new.dni) is not null then
      raise exception 'El documento pertenece a una persona reconocida: solo Gerencia lo corrige (corrección de documento)'
        using errcode = 'P0409';
    end if;
    raise exception 'Con la identidad unificada encendida, el DNI de un lead se fija por su puerta (fijar_dni_lead_fn) o lo corrige Gerencia'
      using errcode = 'P0409';
  elsif v_priv and new.inversionista_id is not null then
    -- Una RPC bajo válvula que ya trae el enlace (p. ej. una fusión futura) manda.
    return new;
  end if;

  if nullif(pg_catalog.btrim(coalesce(new.dni,'')), '') is null then
    new.inversionista_id := null;
    return new;
  end if;
  -- El advisory documental ya lo tomó el trigger 000 en esta misma sentencia.
  v_inv := private.inversionista_por_documento('DNI', new.dni);
  if v_inv is null then
    new.inversionista_id := null;
    return new;
  end if;
  -- Un solo lead TOTAL por persona (invariante #6): vivos, convertidos y descartados.
  -- F2.b [D-13]: enlace vivo ∪ PUENTE ∪ sueltos vivos con su documento (private.leads_de_personas; el enlace vivo primero en
  -- el detalle) y persona EN CONVERSIÓN (reserva por persona viva o sellada de otro lead). Serializado con la reserva por el
  -- candado documental que ya tomó el trigger 000 (inv_resolver:DNI:<doc>, la misma clave que toma la reserva; b1).
  select x as id, coalesce(resp.nombre_completo, 'sin asesor asignado') as asesor
    into v_otro
  from private.leads_de_personas(array[v_inv]) x
  join crm.inversionistas i on i.id = v_inv
  left join public.perfiles resp on resp.id = i.responsable_relacion_id
  where x is distinct from new.id
  order by (exists (select 1 from crm.leads l where l.id = x and l.inversionista_id = v_inv)) desc, x
  limit 1;
  if found then
    raise exception 'Contacto no disponible'
      using errcode = 'P0481',
            detail = pg_catalog.jsonb_build_object(
              'estado', 'ya_es_cliente', 'asesor', v_otro.asesor, 'via', 'identidad', 'lead_id', v_otro.id)::text;
  end if;
  if private.persona_en_conversion(v_inv, new.id)
     or exists (select 1 from crm.inversionistas i where i.id = v_inv and i.perfil_id is not null) then   -- ya cliente (Codex v3 M2)
    raise exception 'Contacto no disponible'
      using errcode = 'P0481',
            detail = pg_catalog.jsonb_build_object(
              'estado', 'ya_es_cliente',
              'asesor', coalesce((select p.nombre_completo
                                    from crm.conversion_reservas r
                                    join public.perfiles p on p.id = r.reservado_por
                                    left join crm.leads lr on lr.id = r.lead_id
                                   where r.inversionista_id = v_inv and r.lead_id is distinct from new.id
                                     and (r.expira_en > pg_catalog.now() or (r.efectos_iniciados_en is not null and coalesce(lr.etapa, '') <> 'convertido'))
                                   order by r.reservado_en desc limit 1), 'sin asesor asignado'),
              'via', 'identidad',
              'lead_id', (select r.lead_id from crm.conversion_reservas r
                           left join crm.leads lr on lr.id = r.lead_id
                           where r.inversionista_id = v_inv and r.lead_id is distinct from new.id
                             and (r.expira_en > pg_catalog.now() or (r.efectos_iniciados_en is not null and coalesce(lr.etapa, '') <> 'convertido'))
                           order by r.reservado_en desc limit 1))::text;
  end if;
  new.inversionista_id := v_inv;
  return new;
end;
$function$
