-- TRINQUETE DE AUDITORÍA (P-055 F1.4/F1.5/F1.6) — `npm run gate:auditoria`.
--
-- La regla ESTRUCTURAL: toda tabla de `crm` y `public` deja rastro COMPLETO Y
-- EFECTIVO en public.audit_log. Las excepciones no se heredan del olvido: viven
-- en `private.auditoria_exenciones` (sin rastro) o `private.auditoria_condicionada`
-- (rastro con condición), siempre CON su razón, y están espejadas aquí abajo.
--
-- 🔴 EL CUERPO DEL GATE NO VIVE AQUÍ, vive en `private.assert_auditoria()`: así
--    el mutante ejecuta EXACTAMENTE esta comprobación bajo cada mutación. Antes
--    el mutante probaba las piezas por separado y podía quedarse verde con el
--    gate roto (hallazgo de Codex).
--
-- 🔴 EL VEREDICTO VIAJA COMO FILA: el canal `supabase db query` NO transporta
--    los `raise notice` (medido). Un gate que buscara su «OK» en un aviso
--    estaría siempre verde por vacío.
do $trinquete$
declare
  -- ⬇ ESPEJO de las dos listas: tabla + razón. Si cambia una, cambia la otra.
  v_exentas_esperadas constant text[] := array[
    'crm.usuario_eventos', 'public.audit_log', 'public.novedades_leidas'];
  v_condicionadas_esperadas constant text[] := array['public.cronograma_pagos'];
  v_vivas text[];
begin
  if pg_catalog.to_regprocedure('private.assert_auditoria()') is null then
    raise exception 'La regla no está en el servidor: falta aplicar la F1.6 (20260829235000)';
  end if;

  -- FILO 1+2: la regla, el sello, el cron y las alertas — todo en el servidor
  perform private.assert_auditoria();

  -- FILO 3: las listas vivas == las escritas en el repo (nombres; el TEXTO de
  -- cada razón lo cubre el sello, que assert_auditoria ya comprobó)
  select pg_catalog.array_agg(e.tabla order by e.tabla) into v_vivas
  from private.auditoria_exenciones e;
  if coalesce(v_vivas, '{}'::text[]) <> v_exentas_esperadas then
    raise exception using errcode = 'P0001',
      message = 'LISTA BLANCA DESALINEADA: la base dice [' ||
        coalesce(pg_catalog.array_to_string(v_vivas, ', '), '(vacía)') ||
        '] y este archivo dice [' || pg_catalog.array_to_string(v_exentas_esperadas, ', ') || '].';
  end if;

  select pg_catalog.array_agg(c.tabla order by c.tabla) into v_vivas
  from private.auditoria_condicionada c;
  if coalesce(v_vivas, '{}'::text[]) <> v_condicionadas_esperadas then
    raise exception using errcode = 'P0001',
      message = 'AUDITORÍA CONDICIONADA DESALINEADA: la base dice [' ||
        coalesce(pg_catalog.array_to_string(v_vivas, ', '), '(vacía)') ||
        '] y este archivo dice [' || pg_catalog.array_to_string(v_condicionadas_esperadas, ', ') || '].';
  end if;
end
$trinquete$;

-- La fila del veredicto: esto es lo que el gate exige ver.
select 'TRINQUETE_AUDITORIA_OK' as veredicto,
       (select pg_catalog.count(*) from private.tablas_sin_rastro()) as sin_rastro,
       (select pg_catalog.count(*) from private.auditoria_exenciones) as exenciones,
       (select pg_catalog.count(*) from private.auditoria_condicionada) as condicionadas,
       (select pg_catalog.count(*) from private.auditoria_alertas where resuelta_en is null) as alertas_abiertas;
