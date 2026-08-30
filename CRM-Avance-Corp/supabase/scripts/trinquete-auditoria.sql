-- TRINQUETE DE AUDITORÍA (P-055 F1.4/F1.5) — corre con `npm run gate:auditoria`.
--
-- La regla ESTRUCTURAL: toda tabla de `crm` y `public` deja rastro COMPLETO en
-- public.audit_log — trigger activo, por fila, auditor conocido y los tres
-- verbos. Las excepciones no se heredan del olvido: viven en
-- `private.auditoria_exenciones` CON su razón, y están copiadas aquí abajo.
--
-- TRES FILOS, y este archivo es el tercero:
--   1. `private.tablas_sin_rastro()` — la regla, dentro del servidor.
--   2. El vigía diario (pg_cron, `private.vigia_auditoria`) — mira el estado
--      aunque nadie corra nada, y vigila también la lista blanca por su sello.
--   3. Este gate — no deja publicar con la regla rota, y comprueba que la lista
--      blanca VIVA sea exactamente la escrita aquí: un cambio hecho directo en
--      la base, sin pasar por el repo, también lo pone en rojo.
--
-- 🔴 EL VEREDICTO VIAJA COMO FILA, NO COMO AVISO: el canal `supabase db query`
--    NO transporta los `raise notice` (medido). Un gate que buscara su «OK» en
--    un aviso estaría siempre en verde por vacío. Por eso el bloque termina y la
--    última sentencia devuelve la fila que el gate exige ver.
do $trinquete$
declare
  -- ⬇ ESPEJO de private.auditoria_exenciones. Si cambia una, cambia la otra.
  --   · crm.usuario_eventos     → es la bitácora misma; y su id BIGINT rompería
  --                               el auditor del CRM (castea a uuid).
  --   · public.novedades_leidas → marca de «leído»; no es dinero ni secreto.
  --   · public.audit_log        → es la auditoría: auditarla sería recursivo.
  v_esperadas constant text[] := array[
    'crm.usuario_eventos', 'public.audit_log', 'public.novedades_leidas'];
  v_sin_rastro text;
  v_cuantas int;
  v_vivas text[];
  v_alertas text;
begin
  if pg_catalog.to_regprocedure('private.tablas_sin_rastro()') is null then
    raise exception 'La regla no está en el servidor: falta aplicar 20260829230000 (F1.4) y 20260829233000 (F1.5)';
  end if;

  -- FILO 1: la regla
  select pg_catalog.count(*), pg_catalog.string_agg(s.tabla, ', ')
    into v_cuantas, v_sin_rastro
  from private.tablas_sin_rastro() s;

  if v_cuantas > 0 then
    raise exception using
      errcode = 'P0001',
      message = 'TRINQUETE DE AUDITORÍA ROTO: ' || v_cuantas || ' tabla(s) sin rastro completo [' ||
        v_sin_rastro || ']. Cuélgale el auditor para los TRES verbos ' ||
        '(private.log_audit_crm, public.log_audit_change, o ' ||
        'private.log_audit_sin_secretos con sus columnas si guarda secretos) o ' ||
        'declárala en private.auditoria_exenciones CON su razón y cópiala en este archivo.';
  end if;

  -- FILO 3a: la lista blanca viva == la escrita en el repo
  select pg_catalog.array_agg(e.tabla order by e.tabla) into v_vivas
  from private.auditoria_exenciones e;

  if coalesce(v_vivas, '{}'::text[]) <> v_esperadas then
    raise exception using
      errcode = 'P0001',
      message = 'LISTA BLANCA DESALINEADA: la base dice [' ||
        coalesce(pg_catalog.array_to_string(v_vivas, ', '), '(vacía)') ||
        '] y este archivo dice [' || pg_catalog.array_to_string(v_esperadas, ', ') ||
        ']. Una exención sin pasar por el repo no vale.';
  end if;

  -- FILO 3b: el sello del vigía tiene que cuadrar con la lista viva
  if not exists (select 1 from private.auditoria_sello
                 where huella = private.huella_exenciones()) then
    raise exception using
      errcode = 'P0001',
      message = 'SELLO ROTO: la lista blanca cambió sin re-sellar. El vigía ya debería haber abierto la alerta __lista_blanca_alterada.';
  end if;

  -- Alertas abiertas: no rompen (la regla ya dio cero), pero se cuentan
  select pg_catalog.string_agg(a.tabla, ', ') into v_alertas
  from private.auditoria_alertas a where a.resuelta_en is null;
  if v_alertas is not null then
    raise exception using
      errcode = 'P0001',
      message = 'EL VIGÍA TIENE ALERTAS ABIERTAS: ' || v_alertas;
  end if;
end
$trinquete$;

-- La fila del veredicto: esto es lo que el gate exige ver.
select 'TRINQUETE_AUDITORIA_OK' as veredicto,
       (select pg_catalog.count(*) from private.tablas_sin_rastro()) as sin_rastro,
       (select pg_catalog.count(*) from private.auditoria_exenciones) as exenciones,
       (select pg_catalog.count(*) from private.auditoria_alertas where resuelta_en is null) as alertas_abiertas;
