CREATE OR REPLACE FUNCTION crm.atribucion_contrato_fn(p_contrato_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select case
    -- La MISMA regla de visibilidad que ya gobierna los contratos del CRM: se
    -- pregunta a la vista viva en vez de copiar su `where`.
    when not exists (
      select 1 from crm.contratos_cartera v where v.id = p_contrato_id
    ) then null
    else (
      select jsonb_build_object(
        'contrato_id',   c.id,
        'analista_id',   c.analista_cierre_id,
        'analista_nombre', pa.nombre_completo,
        'es_demo',       c.es_demo,
        'registrado_por', pr.nombre_completo,
        -- ATR-3: quien COBRA de verdad (la politica de la cadena de upgrade).
        -- 'cadena' = el contrato pertenece a una cadena de upgrade (el propio
        -- upgrade incluido): toda renovacion suya contara al analista_id de aqui.
        -- 'adoptada' = ademas la atribucion difiere del analista que la proceso.
        'atribucion_efectiva', (
          select jsonb_build_object(
            'cadena',   ef.analista_id is not null,
            'adoptada', ef.analista_id is not null
                        and ef.analista_id is distinct from c.analista_cierre_id,
            'analista_id',     coalesce(ef.analista_id, c.analista_cierre_id),
            'analista_nombre', coalesce(pef.nombre_completo, pa.nombre_completo)
          )
          from (select private.analista_atribuido_cadena(c.id) as analista_id) ef
          left join public.perfiles pef on pef.id = ef.analista_id
        ),
        'reasignaciones', case
          -- El historial con motivos, solo para la autoridad o el propio
          -- analista (A3). Mismo conjunto que la policy de la tabla, con P04.
          when (((select public.es_gestor_cartera())
                 or coalesce(private.rol_crm((select auth.uid())) = 'gerencia', false))
                and not (select private.membresia_crm_revocada()))
               or c.analista_cierre_id = (select auth.uid())
          then coalesce((
            select jsonb_agg(jsonb_build_object(
              'cuando',  r.reasignado_en,
              'de',      pde.nombre_completo,
              'a',       pa2.nombre_completo,
              'motivo',  r.motivo,
              'por',     ppor.nombre_completo
            ) order by r.reasignado_en desc)
            from crm.reasignaciones_analista r
            left join public.perfiles pde  on pde.id  = r.analista_de
            left join public.perfiles pa2  on pa2.id  = r.analista_a
            left join public.perfiles ppor on ppor.id = r.reasignado_por
            where r.contrato_id = c.id
          ), '[]'::jsonb)
          else '[]'::jsonb
        end
      )
      from public.contratos c
      left join public.perfiles pa on pa.id = c.analista_cierre_id
      left join public.perfiles pr on pr.id = c.creado_por
      where c.id = p_contrato_id
    )
  end;
$function$
