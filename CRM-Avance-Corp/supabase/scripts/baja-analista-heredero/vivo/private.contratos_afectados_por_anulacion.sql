CREATE OR REPLACE FUNCTION private.contratos_afectados_por_anulacion(p_lead_id uuid)
 RETURNS SETOF uuid
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$

  select c.id
  from crm.leads l
  cross join lateral (
    -- La FOTO manda. El calculo vivo solo sirve de respaldo: para cierres en
    -- cooperativa (que no pasan por esta tabla) y para responder ANTES de anular.
    select coalesce(
      (select ca.acreditado_a from crm.cierres_avance_anulados ca where ca.lead_id = l.id),
      private.vendedor_acreditado_del_cierre(l.id)
    ) as acreditado_a
  ) q
  join public.contratos c
    on (
      -- (a) enlace directo, cuando alguien lo rellena (legado o manual)
      c.id = l.contrato_id
      -- (b) el enlace del flujo REAL: el lead apunta al CLIENTE.
      or (l.perfil_id is not null
          and l.perfil_id = c.cliente_id
          and l.convertido_en is not null
          -- SUELO: un contrato ANTERIOR a la conversion no lo produjo este
          -- cierre. `crm.convertir_lead` admite un cliente que YA existia, asi
          -- que su cartera previa es de otra historia comercial y no se toca.
          and c.creado_en >= l.convertido_en
          -- TECHO: y deja de reclamar en cuanto ese mismo cliente vuelve a
          -- cerrarse. Sin esto un cierre anulado se quedaba con TODO el futuro
          -- del cliente para siempre — incluida la venta legitima que ese mismo
          -- vendedor le hiciera un ano despues.
          and not exists (
            select 1
            from crm.leads l_post
            where l_post.perfil_id = l.perfil_id
              and l_post.id <> l.id
              and l_post.convertido_en is not null
              -- Orden TOTAL, no parcial: `now()` es constante dentro de una
              -- transaccion, asi que dos conversiones del mismo cliente pueden
              -- empatar al microsegundo. Con `>` a secas ninguna cerraria el
              -- techo de la otra y AMBAS reclamarian los mismos contratos.
              and (l_post.convertido_en, l_post.id) > (l.convertido_en, l.id)
              and l_post.convertido_en <= c.creado_en
          ))
    )
   -- Y solo afecta a quien lo tiene. ATR-4: la verdad de la atribucion es la
   -- CADENA (ATR-1/2) con su caida a analista_cierre_id — `creado_por` era el
   -- REGISTRADOR, no el dueño del merito (leccion del 28/08). Esta funcion es
   -- SOLO INFORMATIVA desde ATR-4 (payload/afecta_cuota — que ahora significa
   -- «afecta la CONVERSION» — y retroceso de etapa): produccion y la deuda de
   -- mes sellado ya no le preguntan.
   and coalesce(private.analista_atribuido_cadena(c.id), c.analista_cierre_id) = q.acreditado_a
   -- Lo que la cuota NO mira, esto tampoco puede prometerlo: sin estos dos
   -- filtros, un contrato en otra moneda o de categoria no contable entraba en
   -- `contratos_afectados` y ponia `afecta_cuota` en true sin que bajara un sol.
   and c.categoria in ('nuevo','renovacion','upgrade')
   and c.moneda in ('PEN','USD')
   -- Y la MISMA regla de ambiguedad que aplica la cuota: un contrato enlazado a
   -- leads de vendedores DISTINTOS ya queda sin atribuir alli, asi que anular no
   -- movera un sol. Sin esto, `afecta_cuota` decia true y no bajaba nada.
   and not exists (
     select 1
     from crm.leads le
     where le.contrato_id = c.id
       and le.vendedor_id is not null
     having count(distinct le.vendedor_id) > 1
   )
  where l.id = p_lead_id

$function$
