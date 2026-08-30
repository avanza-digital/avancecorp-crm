-- TRINQUETE DE AUDITORÍA (P-055 F1.4) — corre con `npm run gate:auditoria`.
--
-- La regla ESTRUCTURAL: toda tabla de `crm` y `public` deja rastro en
-- public.audit_log. Las excepciones no se heredan del olvido: viven en
-- `private.auditoria_exenciones` CON su razón, y están copiadas aquí abajo.
--
-- TRES FILOS, y este archivo es el tercero:
--   1. `private.tablas_sin_rastro()` — la regla, dentro del servidor.
--   2. El vigía diario (pg_cron, `private.vigia_auditoria`) — mira el estado
--      aunque nadie corra nada.
--   3. Este gate — no deja publicar con la regla rota, y además comprueba que
--      la lista blanca VIVA sea exactamente la escrita aquí: un cambio hecho
--      directo en la base, sin pasar por el repo, también lo pone en rojo.
do $trinquete$
declare
  -- ⬇ ESPEJO de private.auditoria_exenciones. Si cambia una, cambia la otra.
  --   · crm.usuario_eventos    → es la bitácora misma; y su id BIGINT rompería
  --                              el auditor del CRM (castea a uuid).
  --   · public.novedades_leidas → marca de «leído»; no es dinero ni secreto.
  v_esperadas constant text[] := array['crm.usuario_eventos', 'public.novedades_leidas'];
  v_sin_rastro text;
  v_cuantas int;
  v_vivas text[];
  v_alertas text;
begin
  if pg_catalog.to_regprocedure('private.tablas_sin_rastro()') is null then
    raise exception 'La regla F1.4 no está en el servidor: falta aplicar la migración 20260829230000_crm_f1_4_regla_de_auditoria.sql';
  end if;

  -- FILO 1: la regla
  select pg_catalog.count(*), pg_catalog.string_agg(s.tabla, ', ')
    into v_cuantas, v_sin_rastro
  from private.tablas_sin_rastro() s;

  if v_cuantas > 0 then
    raise exception using
      errcode = 'P0001',
      message = 'TRINQUETE DE AUDITORÍA ROTO: ' || v_cuantas || ' tabla(s) sin rastro [' ||
        v_sin_rastro || ']. Cuélgale el auditor (private.log_audit_crm, ' ||
        'public.log_audit_change, o private.log_audit_sin_secretos si guarda ' ||
        'secretos) o declárala en private.auditoria_exenciones CON su razón y ' ||
        'cópiala en este archivo.';
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

  -- FILO 3b: lo que el vigía tenga abierto (no rompe: la regla ya dio cero,
  -- pero si algo quedó abierto hay que mirarlo)
  select pg_catalog.string_agg(a.tabla || ' (desde ' ||
           pg_catalog.to_char(a.detectada_en at time zone 'America/Lima', 'DD/MM HH24:MI') || ')', ', ')
    into v_alertas
  from private.auditoria_alertas a where a.resuelta_en is null;

  if v_alertas is not null then
    raise notice 'El vigía tiene alertas abiertas: %', v_alertas;
  end if;

  raise notice 'TRINQUETE DE AUDITORÍA OK: 0 tablas sin rastro · lista blanca alineada (2 exenciones)';
end
$trinquete$;
