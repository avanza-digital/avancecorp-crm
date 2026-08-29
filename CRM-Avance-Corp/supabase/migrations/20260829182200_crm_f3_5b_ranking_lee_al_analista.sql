-- P-055 Fase 3.5b - El ranking y el sello LEEN al analista que cierra (P0-1).
--
-- QUE, en una linea: `private.produccion_mes_por_vendedor` -el nucleo que
-- alimenta el ranking, el cumplimiento de metas y la foto que sella
-- `crm.cerrar_periodo`- pasa a atribuir cada contrato por `analista_cierre_id`
-- ANTES que por sus reglas de siempre. Sin esto, la Fase 3 era decorativa:
-- la ficha decia «la venta es de A» y el podio seguia pagandole a B (P0-1 de
-- la auditoria adversarial de Codex, coincidente con el A4 del auditor RLS).
--
-- LA REGLA NUEVA, y por que es la MINIMA:
--   * si el contrato TIENE analista -> se atribuye a ese analista, pasando por
--     el MISMO cuadro de metas del mes que ya gobierna todo lo demas. Fuera del
--     cuadro => sin atribucion, NUNCA cae a otro actor (la invariante escrita
--     del nucleo vivo, que esta migracion conserva a la letra).
--   * si NO tiene analista (los 12 de la decision 18, el caso declarado, o un
--     alta vieja) -> las reglas de siempre, sin cambios: lead explicito ->
--     autor, con roster.
--
-- QUE CAMBIA EN LOS NUMEROS DE AGOSTO, medido antes de escribir:
--   * los 446 contratos del equipo llevan analista = quien los registro, que es
--     EXACTAMENTE la persona que la regla vieja ya elegia -> paridad.
--   * 001163 pasa a contarle a Adelayda y 001325 a Miguel (decision 6): hoy NO
--     le contaban a nadie, porque los registro gerencia y gerencia no esta en
--     el cuadro de metas. Este es el unico movimiento, y es el decidido.
--   * los 12 de la decision 18 siguen sin contarle a nadie (analista NULL y
--     autor gerencia): el podio arranca limpio, como se decidio.
--   * los demos ya no entran (filtro es_demo, absorbido aqui desde la 182000
--     para no reescribir la misma funcion dos veces).
--
-- POR QUE AQUI Y NO EN LA FASE 4: la Fase 4 unifica CALCULADORAS (16 pantallas
-- a un nucleo). Esto no crea una calculadora: corrige LA QUE YA ES el nucleo,
-- que es el criterio de aceptacion literal de la Fase 3 («el ranking de agosto
-- en adelante es exacto, y ya no depende de quien tipeo»).

begin;

do $parche$
declare
  v_src text; v_nuevo text; v_huella text;
  v_a2 text := '    select
      c.id,
      c.categoria,
      c.moneda,
      c.capital,
      c.creado_por,';
  v_a3 text := '    from public.contratos c
';
  v_a4 text := '      case
        when base.vendedores_distintos>1 then null
        when base.tiene_vendedor_explicito then meta_lead.vendedor_id
        else meta_autor.vendedor_id
      end as vendedor_id,';
  v_a5 text := '    left join crm.metas_vendedor meta_autor
      on meta_autor.meta_periodo_id=p_periodo_id
     and meta_autor.vendedor_id=base.creado_por';
begin
  set local lock_timeout = '5s';

  select p.prosrc, md5(p.prosrc) into v_src, v_huella
  from pg_proc p where p.oid = 'private.produccion_mes_por_vendedor(timestamptz,timestamptz,uuid)'::regprocedure;

  if v_huella <> '67be8405cbe4cf5df64e7f16409f084a' then
    raise exception 'produccion_mes_por_vendedor cambio desde que se midio (huella %): ABORTA', v_huella;
  end if;
  if not exists (select 1 from pg_attribute
                 where attrelid='public.contratos'::regclass
                   and attname in ('analista_cierre_id','es_demo') and not attisdropped
                 group by attrelid having count(*) = 2) then
    raise exception 'Faltan las columnas de 20260829180000: ABORTA';
  end if;

  -- Cada ancla, exactamente una vez.
  if (length(v_src)-length(replace(v_src,v_a2,'')))/length(v_a2) <> 1
   or (length(v_src)-length(replace(v_src,v_a3,'')))/length(v_a3) <> 1
   or (length(v_src)-length(replace(v_src,v_a4,'')))/length(v_a4) <> 1
   or (length(v_src)-length(replace(v_src,v_a5,'')))/length(v_a5) <> 1 then
    raise exception 'Las anclas del nucleo no aparecen exactamente una vez: ABORTA';
  end if;

  v_nuevo := v_src;
  -- (1) la columna nueva viaja en contratos_base
  v_nuevo := replace(v_nuevo, v_a2, replace(v_a2, 'c.creado_por,', 'c.creado_por,
      c.analista_cierre_id,'));
  -- (2) los demos no entran al nucleo (absorbe el sitio que tenia la 182000)
  v_nuevo := replace(v_nuevo, v_a3, '    from (select * from public.contratos where not es_demo) c
');
  -- (3) la atribucion: el analista primero, con el MISMO cuadro de metas
  v_nuevo := replace(v_nuevo, v_a4, '      case
        -- P-055 F3.5b: si la venta tiene analista, es SUYA — validada contra el
        -- cuadro de metas del mes, igual que todo lo demas. Fuera del cuadro,
        -- sin atribucion: NUNCA cae a otro actor.
        when base.analista_cierre_id is not null then meta_analista.vendedor_id
        when base.vendedores_distintos>1 then null
        when base.tiene_vendedor_explicito then meta_lead.vendedor_id
        else meta_autor.vendedor_id
      end as vendedor_id,');
  -- (4) el join del cuadro para el analista
  v_nuevo := replace(v_nuevo, v_a5, v_a5 || '
    left join crm.metas_vendedor meta_analista
      on meta_analista.meta_periodo_id=p_periodo_id
     and meta_analista.vendedor_id=base.analista_cierre_id');

  if v_nuevo = v_src then
    raise exception 'El parche no cambio nada: ABORTA';
  end if;

  execute format(
    'create or replace function private.produccion_mes_por_vendedor('
    'p_ini timestamptz, p_fin timestamptz, p_periodo_id uuid) '
    'returns table(vendedor_id uuid, categoria text, moneda text, contratos_real integer, capital_real numeric) '
    'language sql stable security definer set search_path to '''' as %L', v_nuevo);
end
$parche$;

-- --------------------------------------------------------------- POSTFLIGHT --
do $postflight$
declare
  v_src text; v_secdef boolean; v_cfg text[];
begin
  select p.prosrc, p.prosecdef, p.proconfig into v_src, v_secdef, v_cfg
  from pg_proc p where p.oid = 'private.produccion_mes_por_vendedor(timestamptz,timestamptz,uuid)'::regprocedure;

  if not v_secdef then raise exception 'POSTFLIGHT: dejo de ser SECURITY DEFINER'; end if;
  if v_cfg is null or not (v_cfg @> array['search_path=""']::text[]) then
    raise exception 'POSTFLIGHT: sin search_path vacio (%)', v_cfg; end if;

  if strpos(v_src, 'meta_analista.vendedor_id') = 0
     or strpos(v_src, 'and meta_analista.vendedor_id=base.analista_cierre_id') = 0 then
    raise exception 'POSTFLIGHT: la atribucion por analista no quedo'; end if;
  if strpos(v_src, 'where not es_demo') = 0 then
    raise exception 'POSTFLIGHT: el nucleo sigue contando demos'; end if;
  -- Las reglas viejas SIGUEN (el analista es un escalon NUEVO, no un reemplazo)
  if strpos(v_src, 'when base.tiene_vendedor_explicito then meta_lead.vendedor_id') = 0
     or strpos(v_src, 'else meta_autor.vendedor_id') = 0
     or strpos(v_src, 'externos_confirmados') = 0
     or strpos(v_src, 'neutralizados') = 0 then
    raise exception 'POSTFLIGHT: el parche se llevo por delante una regla viva del nucleo'; end if;

  raise notice 'POSTFLIGHT OK: el ranking y el sello leen al analista que cierra';
end
$postflight$;

commit;
