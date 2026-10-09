CREATE OR REPLACE FUNCTION private.analista_atribuido_cadena(p_contrato_id uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  -- La ADOPCION MAS RECIENTE manda (auditoria Codex P1-1): se camina hacia
  -- atras y gana el PRIMER ancestro (o el propio contrato) con categoria
  -- 'upgrade' — asi una correccion de categoria por la puerta de edicion
  -- corrige tambien la adopcion de sus descendientes, en vez de saltarsela.
  -- Anti-ciclo por lista de visitados (dos filas cruzadas A<->B satisfacen
  -- los UNIQUE del esquema: el tope de nivel NO basta) + tope 100 de cinturon.
  with recursive cadena as (
    select p_contrato_id as contrato_id, 0 as nivel, array[p_contrato_id] as visitados
    union all
    select o.contrato_origen_id, c.nivel + 1, c.visitados || o.contrato_origen_id
      from cadena c
      join crm.operaciones_cartera o on o.contrato_nuevo_id = c.contrato_id
     where o.contrato_origen_id is not null
       and not (o.contrato_origen_id = any(c.visitados))
       and c.nivel < 100
  )
  select con.analista_cierre_id
    from cadena cd
    join public.contratos con on con.id = cd.contrato_id
   where con.categoria = 'upgrade'
   order by cd.nivel asc
   limit 1
$function$
