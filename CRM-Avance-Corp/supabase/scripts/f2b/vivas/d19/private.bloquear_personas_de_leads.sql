CREATE OR REPLACE FUNCTION private.bloquear_personas_de_leads(p_leads uuid[], p_dni_extra text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_personas uuid[]; v_claves text[]; v_k text;
begin
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    return pg_catalog.jsonb_build_object('personas', '[]'::jsonb, 'claves', '[]'::jsonb);
  end if;
  -- Codex v4.3 [2]: la comprobación «sigue dentro de lo bloqueado» relee tras esperar y eso solo vale en READ COMMITTED
  -- (en REPEATABLE READ el snapshot viejo esconde a una persona confirmada por otra transacción).
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'La identidad unificada requiere READ COMMITTED (aislamiento actual: %)', pg_catalog.current_setting('transaction_isolation') using errcode = '0A000';
  end if;
  select pg_catalog.array_agg(distinct p order by p) into v_personas
  from (select private.lead_persona_reabrir(l.id) as p from crm.leads l where l.id = any(coalesce(p_leads, '{}'::uuid[]))
        union select private.inversionista_por_documento('DNI', p_dni_extra) where p_dni_extra is not null) s
  where p is not null;
  select pg_catalog.array_agg(distinct k order by k) into v_claves
  from (select 'DNI:' || l.dni as k from crm.leads l where l.id = any(coalesce(p_leads, '{}'::uuid[])) and l.dni is not null
        union select 'DNI:' || p_dni_extra where p_dni_extra is not null
        union select d.tipo_documento || ':' || d.documento_normalizado
                from crm.inversionista_identificadores d
               where d.inversionista_id = any(coalesce(v_personas, '{}'::uuid[])) and d.estado = 'vigente') s;
  if v_claves is not null then
    foreach v_k in array v_claves loop
      perform private.identidad_bloquear_documento(split_part(v_k, ':', 1), split_part(v_k, ':', 2));
    end loop;
  end if;
  if v_personas is not null then
    perform 1 from crm.inversionistas i where i.id = any(v_personas) order by i.id for share;
  end if;
  -- Codex v4.3 [1]: identidad_bloquear_documento es un no-op si la bandera está APAGADA; si alguien la apagó entre la primera
  -- lectura y los candados, no hay candados reales → no se declara nada bloqueado (el llamador da veredicto fresco / 40001).
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    return pg_catalog.jsonb_build_object('personas', '[]'::jsonb, 'claves', '[]'::jsonb);
  end if;
  -- Devuelve lo que REALMENTE bloqueó (Codex v4.2, ABA): el llamador, tras tomar la fila, exige que el documento actual
  -- del lead esté entre las claves bloqueadas y su persona entre las bloqueadas; si no, veredicto fresco / 40001.
  return pg_catalog.jsonb_build_object('personas', pg_catalog.to_jsonb(coalesce(v_personas, '{}'::uuid[])),
                                       'claves', pg_catalog.to_jsonb(coalesce(v_claves, '{}'::text[])));
end;
$function$
